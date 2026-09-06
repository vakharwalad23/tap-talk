export const site = {
	name: "TapTalk",
	url: "https://taptalk.dhruvvakharwala.dev",
	repoUrl: "https://github.com/vakharwalad23/tap-talk",
	repoSlug: "vakharwalad23/tap-talk",
	downloadUrl: "https://github.com/vakharwalad23/tap-talk/releases/latest",
	releasesUrl: "https://github.com/vakharwalad23/tap-talk/releases",
	issuesUrl: "https://github.com/vakharwalad23/tap-talk/issues",
	licenseUrl: "https://github.com/vakharwalad23/tap-talk/blob/main/LICENSE",
	authorName: "Dhruv Vakharwala",
	authorUrl: "https://github.com/vakharwalad23",
	version: "0.3.0",
	lastUpdated: "2026-09-06",
	title: "TapTalk - Free On-Device Dictation for Mac",
	description:
		"Press a key, speak, paste. TapTalk is a free, open-source Mac dictation app that runs 100 percent on-device on the Neural Engine. No account, no subscription, no cloud.",
	shortDescription:
		"Free, open-source, 100 percent on-device dictation app for Mac. Press a key, speak, and your words are transcribed on the Apple Neural Engine and pasted into any app, with no account, no subscription, and no cloud.",
	brewCommand: "brew install --cask vakharwalad23/tap/taptalk",
	requirements: "macOS 14 or later. Apple Silicon (M1 to M4).",
	ogImagePath: "/og.png",
} as const;

export const hero = {
	eyebrow: "Free. Open source. 100 percent on-device.",
	headline: "Don't type. Just talk.",
	sub: "TapTalk turns speech into text in any Mac app. Hold a key, speak, release, and it is pasted where your cursor is. It runs entirely on your Mac's Neural Engine. No account, no subscription, no cloud.",
	makerNote:
		"Built by one developer, in the open. It is not notarized by Apple yet, so on first launch use right-click then Open, or install with Homebrew, which handles it for you.",
	demo: {
		raw: "um so send her the uh the report by like friday no wait thursday",
		clean: "Send her the report by Thursday.",
		caption: "With Smart Mode on. Cleanup runs locally.",
	},
} as const;

export const valueTiles = [
	{
		title: "Free and open source",
		body: "MIT licensed. No subscription, no trial, no paywall. Auditable and forkable on GitHub.",
	},
	{
		title: "100 percent on-device",
		body: "Transcription runs on the Apple Neural Engine. Your audio never leaves your Mac. No account, no telemetry.",
	},
	{
		title: "It cleans up as you speak",
		body: "An optional local AI rewrite fixes filler and grammar and matches the app you are writing in, all on your machine.",
	},
	{
		title: "Truly native",
		body: "SwiftUI plus Rust. No Electron, no web wrapper. Small, fast, light on battery.",
	},
] as const;

export const notList = [
	"no account",
	"no subscription",
	"no telemetry",
	"no cloud by default",
] as const;
