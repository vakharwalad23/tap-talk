use crate::platform::ChipFamily;

/// Per-chip / per-tier streaming cadence. Slower encoders (M1) use fewer, larger
/// segments so decode keeps up with live audio; faster chips chunk aggressively.
#[derive(Clone, Copy, Debug)]
pub struct StreamTuning {
    pub endpoint_silence_ms: u32,
    pub min_segment_ms: u32,
    pub max_segment_ms: u32,
}

pub fn tuning_for(family: ChipFamily, tier_id: u8) -> StreamTuning {
    let base = match family {
        ChipFamily::M1 => StreamTuning {
            endpoint_silence_ms: 450,
            min_segment_ms: 700,
            max_segment_ms: 7000,
        },
        ChipFamily::M2 => StreamTuning {
            endpoint_silence_ms: 350,
            min_segment_ms: 600,
            max_segment_ms: 8000,
        },
        ChipFamily::M3 => StreamTuning {
            endpoint_silence_ms: 300,
            min_segment_ms: 500,
            max_segment_ms: 9000,
        },
        ChipFamily::M4 | ChipFamily::M5 => StreamTuning {
            endpoint_silence_ms: 300,
            min_segment_ms: 500,
            max_segment_ms: 10_000,
        },
        ChipFamily::Unknown => StreamTuning {
            endpoint_silence_ms: 400,
            min_segment_ms: 600,
            max_segment_ms: 8000,
        },
    };

    // Large v3 (tier 4) has 32 decoder layers — decode dominates, so prefer
    // fewer, larger segments to avoid falling behind.
    if tier_id == 4 {
        StreamTuning {
            min_segment_ms: base.min_segment_ms * 3 / 2,
            ..base
        }
    } else {
        base
    }
}
