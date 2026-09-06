import type { IconName } from "#/components/ui/Icon";
import type { LogoName } from "./logo-paths";

export interface LogoEntry {
	readonly name: string;
	readonly role: string;
	readonly url: string;
	readonly logo?: LogoName;
	// Fallback glyph for projects without a simple-icons mark.
	readonly icon?: IconName;
	readonly license?: string;
}

export const builtWith: readonly LogoEntry[] = [
	{
		name: "Rust",
		role: "the audio core",
		url: "https://www.rust-lang.org",
		logo: "rust",
	},
	{
		name: "Swift",
		role: "the app and UI",
		url: "https://www.swift.org",
		logo: "swift",
	},
	{
		name: "Apple Silicon and Core ML",
		role: "Neural Engine inference",
		url: "https://developer.apple.com/machine-learning/core-ml/",
		icon: "chip",
	},
	{
		name: "FluidAudio",
		role: "Core ML speech runtime",
		url: "https://github.com/FluidInference/FluidAudio",
		icon: "mic",
	},
	{
		name: "llama.cpp",
		role: "local LLM runtime",
		url: "https://github.com/ggml-org/llama.cpp",
		icon: "terminal",
	},
	{
		name: "UniFFI",
		role: "Rust to Swift bridge",
		url: "https://mozilla.github.io/uniffi-rs/",
		icon: "code",
	},
	{
		name: "Homebrew",
		role: "one-line install",
		url: "https://brew.sh",
		logo: "homebrew",
	},
];

export const models: readonly LogoEntry[] = [
	{
		name: "NVIDIA Parakeet TDT 0.6B v3",
		role: "default speech recognition, English and European",
		url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml",
		logo: "nvidia",
		license: "CC-BY-4.0",
	},
	{
		name: "NVIDIA Nemotron 3.5 ASR Multilingual 0.6B",
		role: "Hindi and more",
		url: "https://huggingface.co/FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML",
		logo: "nvidia",
		license: "OpenMDW-1.1",
	},
	{
		name: "NVIDIA Parakeet Realtime EOU 120M",
		role: "live typing add-on",
		url: "https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml",
		logo: "nvidia",
		license: "NVIDIA Open Model License",
	},
	{
		name: "Qwen 2.5 1.5B Instruct",
		role: "Smart Mode rewrite",
		url: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF",
		logo: "qwen",
		license: "Apache-2.0",
	},
];

export const logosDisclaimer =
	"Logos belong to their owners and are shown to credit the open technology TapTalk is built on. Models are downloaded from Hugging Face at runtime; TapTalk ships no weights.";

export const siteBuiltWith: readonly LogoEntry[] = [
	{
		name: "TypeScript",
		role: "",
		url: "https://www.typescriptlang.org",
		logo: "typescript",
	},
	{ name: "React", role: "", url: "https://react.dev", logo: "react" },
	{ name: "Vite", role: "", url: "https://vite.dev", logo: "vite" },
	{
		name: "Cloudflare",
		role: "",
		url: "https://workers.cloudflare.com",
		logo: "cloudflare",
	},
];
