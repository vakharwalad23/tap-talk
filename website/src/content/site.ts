// Bump on each release. The asset name is fixed by the Makefile (dist/TapTalk-$(VERSION).dmg)
// and by the Homebrew cask, so this one value keeps the direct download link current.
const version = "0.3.0";

export const site = {
	name: "TapTalk",
	url: "https://taptalk.dhruvvakharwala.dev",
	repoUrl: "https://github.com/vakharwalad23/tap-talk",
	repoSlug: "vakharwalad23/tap-talk",
	// GitHub answers this with a 302 to the asset and Content-Disposition: attachment, so the
	// browser downloads the DMG without leaving the page.
	downloadUrl: `https://github.com/vakharwalad23/tap-talk/releases/download/v${version}/TapTalk-${version}.dmg`,
	releasesUrl: "https://github.com/vakharwalad23/tap-talk/releases",
	issuesUrl: "https://github.com/vakharwalad23/tap-talk/issues",
	licenseUrl: "https://github.com/vakharwalad23/tap-talk/blob/main/LICENSE",
	authorName: "Dhruv Vakharwala",
	authorUrl: "https://github.com/vakharwalad23",
	version,
	lastUpdated: "2026-09-06",
	title: "TapTalk - Free On-Device Dictation for Mac",
	// Under 160 characters so search snippets show the whole sentence.
	description:
		"Free, open-source Mac dictation that runs 100 percent on-device on the Neural Engine. Press a key, speak, paste. No account, no subscription, no cloud.",
	shortDescription:
		"Free, open-source, 100 percent on-device dictation app for Mac. Press a key, speak, and your words are transcribed on the Apple Neural Engine and pasted into any app, with no account, no subscription, and no cloud.",
	brewCommand: "brew install --cask vakharwalad23/tap/taptalk",
	requirements: "macOS 14 or later. Any Apple Silicon Mac.",
	chipNote:
		"Every Apple Silicon Mac is supported. The Neural Engine gets faster with each generation, so an M3 or M4 feels instant and an M1 or M2 takes a beat longer.",
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
		plain: "Um so send her the uh the report by like Friday no wait Thursday.",
		clean: "Send her the report by Thursday.",
		speakLabel: "You speak",
		plainLabel: "Plain key, pasted as you said it",
		smartLabel: "Smart key, cleaned up on your Mac",
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
