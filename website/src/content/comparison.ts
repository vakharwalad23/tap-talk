export type Verdict = "yes" | "no" | "partial";

export interface Cell {
	readonly verdict: Verdict;
	readonly note?: string;
}

export interface Rival {
	readonly name: string;
	readonly url: string;
	readonly price: string;
	readonly cells: readonly Cell[];
	readonly platforms: string;
}

export const comparisonCriteria = [
	"Open source",
	"Ready-to-run free binary",
	"On-device by default",
	"Works offline",
	"Neural Engine",
	"Built-in local AI rewrite",
	"Context-aware",
	"Native UI",
	"No account needed",
	"Hindi plus Hinglish",
] as const;

const y = (note?: string): Cell => ({ verdict: "yes", note });
const n = (note?: string): Cell => ({ verdict: "no", note });
const p = (note?: string): Cell => ({ verdict: "partial", note });

export const taptalkRow: Rival = {
	name: "TapTalk",
	url: "https://github.com/vakharwalad23/tap-talk",
	price: "Free",
	cells: [
		y("MIT"),
		y(),
		y("Neural Engine"),
		y(),
		y(),
		y("no setup"),
		y("local"),
		y("SwiftUI plus Rust"),
		y(),
		y("with romanization"),
	],
	platforms: "macOS, Apple Silicon",
};

export const rivals: readonly Rival[] = [
	{
		name: "Wispr Flow",
		url: "https://wisprflow.ai",
		price: "USD 15/mo, 12 annual",
		cells: [
			n(),
			y("paid"),
			n("cloud only"),
			n(),
			n("cloud"),
			y("cloud"),
			y("cloud"),
			p("not stated"),
			n(),
			p("unverified"),
		],
		platforms: "Mac, Win, iOS, Android",
	},
	{
		name: "superwhisper",
		url: "https://superwhisper.com",
		price: "Free tier, USD 8.49/mo or 249.99 lifetime",
		cells: [
			n(),
			y(),
			p("best models cloud or Pro"),
			y("local mode"),
			p("varies"),
			y("cloud or Pro"),
			y(),
			p("not stated"),
			n(),
			p("100 plus langs"),
		],
		platforms: "Mac, Win, iOS",
	},
	{
		name: "MacWhisper",
		url: "https://www.macwhisper.com",
		price: "Free tier, EUR 64 one-time",
		cells: [
			n("uses whisper.cpp"),
			y("paid Pro"),
			y(),
			y(),
			p("via WhisperKit"),
			p("cloud key or Ollama"),
			p("limited"),
			y(),
			y("local"),
			p("Whisper langs"),
		],
		platforms: "Mac, iOS",
	},
	{
		name: "VoiceInk",
		url: "https://tryvoiceink.com",
		price: "USD 25 to 49 one-time, or compile",
		cells: [
			y("GPLv3"),
			n("paid, or compile"),
			y(),
			y(),
			p("Whisper default"),
			p("needs Ollama"),
			y("Power Mode"),
			y(),
			y(),
			p("Hindi model"),
		],
		platforms: "macOS",
	},
	{
		name: "Handy",
		url: "https://github.com/cjpais/Handy",
		price: "Free",
		cells: [
			y("MIT"),
			y(),
			y(),
			y(),
			n("CPU or GPU"),
			n(),
			n(),
			n("Tauri web"),
			y(),
			n(),
		],
		platforms: "Mac, Win, Linux",
	},
	{
		name: "Apple Dictation",
		url: "https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac",
		price: "Free, built in",
		cells: [
			n(),
			y("built in"),
			y("Apple Silicon"),
			y("supported langs"),
			y(),
			n(),
			n(),
			y("system"),
			y(),
			p(),
		],
		platforms: "Apple OSes",
	},
];

export const comparisonIntro =
	"TapTalk is the only Mac dictation app that is free, permissively open source, shipped as a ready-to-run binary, 100 percent on-device by default on the Neural Engine, natively built, and includes a local context-aware AI rewrite, with no account and no subscription.";

export const comparisonCallouts = [
	{
		versus: "Wispr Flow and Aqua Voice",
		text: "Powerful, but cloud-only and subscription-based. Your audio goes to their servers, and they stop working offline. Wispr's own privacy page says transcription always happens in the cloud. TapTalk keeps everything on your Mac, for free.",
	},
	{
		versus: "superwhisper",
		text: "A good app, but its best models are cloud or Pro, it needs an account, and it reportedly saves recordings to iCloud by default. TapTalk is free, account-free, and local by default.",
	},
	{
		versus: "VoiceInk",
		text: "Also open source and local, but the ready-made app is paid (USD 25 to 49), it is GPLv3, and its AI cleanup needs you to run Ollama. TapTalk's binary is free, MIT, and ships the local rewrite built in.",
	},
	{
		versus: "Handy",
		text: "Free and MIT like us, and cross-platform, but its UI is a Tauri web wrapper, it does not use the Neural Engine, there is no built-in AI rewrite, and no Hindi or Hinglish. TapTalk is native, ANE-accelerated, and smarter out of the box.",
	},
	{
		versus: "Apple Dictation",
		text: "Free and built in, but no AI cleanup, no context, a fixed model you cannot upgrade, and it falls back to Apple's servers for many languages. TapTalk gives you swappable on-device models and a local rewrite.",
	},
] as const;

export const comparisonSourcesNote =
	"Compiled from each product's official site and pricing pages, September 2026. Corrections welcome, open an issue.";
