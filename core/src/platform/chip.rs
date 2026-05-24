use std::ffi::CString;
use std::sync::OnceLock;

/// Apple Silicon M-series generation. The per-generation variants all share the same
/// GPU/Neural Engine architecture, so only the generation is tracked — the variant word
/// is ignored:
///   M1: M1 · M1 Pro · M1 Max · M1 Ultra
///   M2: M2 · M2 Pro · M2 Max · M2 Ultra
///   M3: M3 · M3 Pro · M3 Max · M3 Ultra
///   M4: M4 · M4 Pro · M4 Max
///   M5: M5 · M5 Pro · M5 Max · M5 Ultra
/// `Newer(n)` covers generations released after this catalog (M6+); `Unknown` is a
/// non-M-series or undetectable chip.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ChipFamily {
    M1,
    M2,
    M3,
    M4,
    M5,
    Newer(u32),
    Unknown,
}

impl ChipFamily {
    fn from_generation(generation: u32) -> Self {
        match generation {
            0 => ChipFamily::Unknown,
            1 => ChipFamily::M1,
            2 => ChipFamily::M2,
            3 => ChipFamily::M3,
            4 => ChipFamily::M4,
            5 => ChipFamily::M5,
            n => ChipFamily::Newer(n),
        }
    }

    /// Flash-attention is stable on M2 and every newer generation; M1's GPU is flaky
    /// with it on some attention shapes. Unknown chips default to off (conservative).
    pub fn supports_flash_attn(self) -> bool {
        match self {
            ChipFamily::M1 | ChipFamily::Unknown => false,
            ChipFamily::M2
            | ChipFamily::M3
            | ChipFamily::M4
            | ChipFamily::M5
            | ChipFamily::Newer(_) => true,
        }
    }
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
    ChipFamily::from_generation(parse_generation(brand))
}

/// Extracts the M-series generation from the brand string, e.g. "Apple M3 Max" -> 3.
/// Matches the `Mn` token exactly (digits only) so the variant word ("Pro"/"Max"/
/// "Ultra") is ignored and a future "M10" isn't mistaken for "M1". Returns 0 if none.
fn parse_generation(brand: &str) -> u32 {
    for token in brand.split_whitespace() {
        if let Some(rest) = token.strip_prefix(['M', 'm']) {
            if !rest.is_empty() && rest.bytes().all(|b| b.is_ascii_digit()) {
                if let Ok(n) = rest.parse::<u32>() {
                    return n;
                }
            }
        }
    }
    0
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
    fn family_parsing_all_variants() {
        // Every variant of a generation maps to that generation.
        for (brand, expected) in [
            ("Apple M1", ChipFamily::M1),
            ("Apple M1 Pro", ChipFamily::M1),
            ("Apple M1 Max", ChipFamily::M1),
            ("Apple M1 Ultra", ChipFamily::M1),
            ("Apple M2", ChipFamily::M2),
            ("Apple M2 Pro", ChipFamily::M2),
            ("Apple M2 Max", ChipFamily::M2),
            ("Apple M2 Ultra", ChipFamily::M2),
            ("Apple M3", ChipFamily::M3),
            ("Apple M3 Pro", ChipFamily::M3),
            ("Apple M3 Max", ChipFamily::M3),
            ("Apple M3 Ultra", ChipFamily::M3),
            ("Apple M4", ChipFamily::M4),
            ("Apple M4 Pro", ChipFamily::M4),
            ("Apple M4 Max", ChipFamily::M4),
            ("Apple M5", ChipFamily::M5),
            ("Apple M5 Pro", ChipFamily::M5),
            ("Apple M5 Max", ChipFamily::M5),
            ("Apple M5 Ultra", ChipFamily::M5),
        ] {
            assert_eq!(parse_family(brand), expected, "brand: {brand}");
        }
    }

    #[test]
    fn future_and_unknown_chips() {
        assert_eq!(parse_family("Apple M6 Max"), ChipFamily::Newer(6));
        assert_eq!(parse_family("Apple M10 Pro"), ChipFamily::Newer(10));
        assert_eq!(parse_family("Apple A12"), ChipFamily::Unknown);
        assert_eq!(parse_family("Intel Core i7"), ChipFamily::Unknown);
        assert_eq!(parse_family(""), ChipFamily::Unknown);
    }

    #[test]
    fn flash_attn_gating() {
        assert!(!ChipFamily::M1.supports_flash_attn());
        assert!(!ChipFamily::Unknown.supports_flash_attn());
        assert!(ChipFamily::M2.supports_flash_attn());
        assert!(ChipFamily::M5.supports_flash_attn());
        assert!(ChipFamily::Newer(6).supports_flash_attn());
    }
}
