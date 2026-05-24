use std::ffi::CString;
use std::sync::OnceLock;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ChipFamily {
    M1,
    M2,
    M3,
    M4,
    Unknown,
}

#[derive(Clone, Copy, Debug)]
pub struct ChipInfo {
    pub family: ChipFamily,
    pub performance_cores: u32,
}

static CACHED: OnceLock<ChipInfo> = OnceLock::new();

pub fn detect() -> ChipInfo {
    *CACHED.get_or_init(detect_uncached)
}

fn detect_uncached() -> ChipInfo {
    let brand = sysctl_string("machdep.cpu.brand_string").unwrap_or_default();
    let family = parse_family(&brand);
    let performance_cores = sysctl_u32("hw.perflevel0.physicalcpu").unwrap_or(4);
    ChipInfo { family, performance_cores }
}

fn parse_family(brand: &str) -> ChipFamily {
    if brand.contains("M4") {
        ChipFamily::M4
    } else if brand.contains("M3") {
        ChipFamily::M3
    } else if brand.contains("M2") {
        ChipFamily::M2
    } else if brand.contains("M1") {
        ChipFamily::M1
    } else {
        ChipFamily::Unknown
    }
}

fn sysctl_u32(name: &str) -> Option<u32> {
    let mut value: u32 = 0;
    let mut size = std::mem::size_of::<u32>();
    let cname = CString::new(name).ok()?;
    // SAFETY: cname is a valid NUL-terminated string, value/size point to a properly-sized u32.
    let rc = unsafe {
        libc::sysctlbyname(
            cname.as_ptr(),
            &mut value as *mut u32 as *mut libc::c_void,
            &mut size,
            std::ptr::null_mut(),
            0,
        )
    };
    if rc == 0 { Some(value) } else { None }
}

fn sysctl_string(name: &str) -> Option<String> {
    let cname = CString::new(name).ok()?;
    let mut size: usize = 0;
    // SAFETY: cname is NUL-terminated; passing null oldp queries required size.
    let rc = unsafe {
        libc::sysctlbyname(
            cname.as_ptr(),
            std::ptr::null_mut(),
            &mut size,
            std::ptr::null_mut(),
            0,
        )
    };
    if rc != 0 || size == 0 {
        return None;
    }
    let mut buf = vec![0u8; size];
    // SAFETY: buf has `size` bytes capacity; sysctl writes at most `size` bytes.
    let rc = unsafe {
        libc::sysctlbyname(
            cname.as_ptr(),
            buf.as_mut_ptr() as *mut libc::c_void,
            &mut size,
            std::ptr::null_mut(),
            0,
        )
    };
    if rc != 0 {
        return None;
    }
    if let Some(end) = buf.iter().position(|&b| b == 0) {
        buf.truncate(end);
    }
    String::from_utf8(buf).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_some_chip_on_macos() {
        let info = detect();
        assert!(info.performance_cores >= 1);
    }

    #[test]
    fn family_parsing() {
        assert_eq!(parse_family("Apple M1 Pro"), ChipFamily::M1);
        assert_eq!(parse_family("Apple M2 Max"), ChipFamily::M2);
        assert_eq!(parse_family("Apple M3"), ChipFamily::M3);
        assert_eq!(parse_family("Apple M4 Pro"), ChipFamily::M4);
        assert_eq!(parse_family("Apple A12"), ChipFamily::Unknown);
    }
}
