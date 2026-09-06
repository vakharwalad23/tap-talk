export const speed = {
	title: "Fast because it is native, and because it runs on the Neural Engine.",
	body: "TapTalk is built for the only number that matters: the time from releasing the key to seeing your text. Models are prewarmed while you are still talking, audio capture is a zero-allocation Rust core, and recognition runs on the Apple Neural Engine, so plain dictation lands in well under a second once warm.",
	stats: [
		{ value: "Sub-second", label: "plain dictation once warm, on-device" },
		{ value: "14.5%", label: "Hindi word error rate on 418 real FLEURS clips" },
		{
			value: "~164 MB",
			label: "resident with a model loaded, weights memory-mapped",
		},
		{ value: "0", label: "bytes of audio sent anywhere by default" },
	],
	benchmark: {
		title: "Hindi accuracy, lower is better",
		rows: [
			{ name: "TapTalk (Nemotron)", wer: 14.5, highlight: true },
			{ name: "IndicWhisper", wer: 15 },
			{ name: "Qwen3-ASR 8-bit", wer: 18.6 },
			{ name: "Apple Dictation", wer: 31.6 },
		],
		note: "Word error rate on all 418 FLEURS hi_in clips, measured on an M3 Pro.",
	},
} as const;

export const openSource = {
	title: "Open source, and built for contributors.",
	body: "TapTalk is MIT licensed. Read every line, fork it, change it, ship your own build. If you make it better, send it back. Issues and pull requests are welcome.",
	actions: [
		{
			title: "Star it",
			body: "If TapTalk is useful, a star helps others find it.",
		},
		{ title: "Fork it", body: "Make it yours. MIT means no strings." },
		{
			title: "Contribute",
			body: "Good first issues are labeled. PRs are reviewed and merged. This project accepts contributions.",
		},
	],
	makerNote:
		"TapTalk is built by one developer, Dhruv Vakharwala, in the open. It is not notarized by Apple yet, that costs money and time for a solo project, so on first launch you may need to right-click then Open, or install with Homebrew, which clears the Gatekeeper flag for you. Everything is on GitHub, so you never have to trust a black box.",
} as const;

export const tech = {
	title: "Built like a systems tool, not a web app.",
	items: [
		{
			title: "Rust core",
			body: "Real-time audio capture, VAD, gain, resampling. Zero-allocation, real-time-safe. Six audited crates, no heavyweight async runtime.",
		},
		{
			title: "Swift plus Core ML",
			body: "Recognition on the Apple Neural Engine via FluidAudio. Native SwiftUI and AppKit UI.",
		},
		{
			title: "UniFFI bridge",
			body: "A thin, auto-generated FFI between the two. The whole surface is reviewable in one file.",
		},
		{
			title: "Models on demand",
			body: "NVIDIA Parakeet and Nemotron for speech, Qwen 2.5 for the rewrite via llama.cpp. Downloaded at runtime, never bundled. TapTalk is a downloader, not a distributor.",
		},
	],
} as const;

export const finalCta = {
	title: "Stop typing. Start talking, privately.",
	body: "Free, open source, and on your Mac in about two minutes.",
} as const;
