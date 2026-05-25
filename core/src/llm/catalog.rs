pub struct LlmModelSpec {
    pub id: &'static str,
    pub filename: &'static str,
    pub url: &'static str,
}

pub const LLM_MODELS: [LlmModelSpec; 1] = [
    LlmModelSpec {
        id: "qwen2.5-1.5b",
        filename: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
        url: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf",
    },
];

pub fn llm_model_by_id(id: &str) -> Option<&'static LlmModelSpec> {
    LLM_MODELS.iter().find(|m| m.id == id)
}
