pub struct ModelTier {
    pub id: u8,
    pub name: &'static str,
    pub ggml_filename: &'static str,
    pub coreml_filename: &'static str,
    pub disk_size_mb: u32,
}

pub const TIERS: [ModelTier; 4] = [
    ModelTier {
        id: 1,
        name: "Tiny",
        ggml_filename: "ggml-tiny.bin",
        coreml_filename: "ggml-tiny-encoder.mlmodelc",
        disk_size_mb: 75,
    },
    ModelTier {
        id: 2,
        name: "Small",
        ggml_filename: "ggml-small.bin",
        coreml_filename: "ggml-small-encoder.mlmodelc",
        disk_size_mb: 466,
    },
    ModelTier {
        id: 3,
        name: "Large v3 Turbo",
        ggml_filename: "ggml-large-v3-turbo.bin",
        coreml_filename: "ggml-large-v3-turbo-encoder.mlmodelc",
        disk_size_mb: 1600,
    },
    ModelTier {
        id: 4,
        name: "Large v3",
        ggml_filename: "ggml-large-v3.bin",
        coreml_filename: "ggml-large-v3-encoder.mlmodelc",
        disk_size_mb: 3000,
    },
];

pub fn tier_by_id(id: u8) -> Option<&'static ModelTier> {
    TIERS.iter().find(|t| t.id == id)
}
