export interface FaqItem {
	readonly question: string;
	readonly answer: string;
}

export const faq: readonly FaqItem[] = [
	{
		question: "Is TapTalk free?",
		answer:
			"Yes. TapTalk is completely free and open source (MIT). No subscription, no trial, no paywall, no word limits, and no account.",
	},
	{
		question: "Is my voice or audio ever sent anywhere?",
		answer:
			"No, not by default. Audio is captured and transcribed entirely on your Mac and discarded after. Nothing leaves your machine unless you deliberately enable the optional OpenAI cloud engine with your own key.",
	},
	{
		question: "Does TapTalk work offline?",
		answer:
			"Yes. On-device transcription needs no internet after the one-time model download. You only need a connection to opt into the cloud engine or to download a model.",
	},
	{
		question: "How is it different from Apple's built-in Dictation?",
		answer:
			"TapTalk adds a local AI rewrite that cleans up and formats your text to match the app you are in, lets you swap in stronger on-device models, supports Hindi and Hinglish, and is fully open source. Apple Dictation does none of these.",
	},
	{
		question: "Is it a free alternative to Wispr Flow and Superwhisper?",
		answer:
			"Yes. TapTalk is a free, open-source, on-device alternative. Unlike Wispr Flow (cloud only, subscription) it runs locally with no account, and unlike Superwhisper it is free with the AI rewrite built in.",
	},
	{
		question: "Which Macs does it support?",
		answer:
			"Any Apple Silicon Mac running macOS 14 or later. TapTalk runs on the Neural Engine, which gets faster with every chip generation: an M3 or M4 feels instant, and an M1 or M2 takes a beat longer.",
	},
	{
		question: "Can I use it in any app?",
		answer:
			"Yes, in Mail, Slack, Notion, Xcode, the terminal, browsers, and more. It even works in Electron apps like VS Code and Discord through a paste fallback.",
	},
	{
		question: "Does it support Hindi and other languages?",
		answer:
			"Yes. English and European languages via Parakeet, and Hindi, Marathi, Urdu, Chinese, Japanese and more via Nemotron, all on-device, plus optional Roman-script Hinglish output.",
	},
	{
		question: "Do I need an OpenAI key?",
		answer:
			"No. Everything works fully on-device. A cloud engine is available if you want it, but it is off by default and uses your own key.",
	},
	{
		question: "What is Smart Mode?",
		answer:
			"A second hotkey that transcribes and rewrites with a local language model, removing filler, fixing grammar, resolving spoken corrections, and matching the tone of the app you are writing in.",
	},
	{
		question: "Is TapTalk built with Electron?",
		answer:
			"No. It is a native macOS app built with SwiftUI and Rust, so it is small and fast and does not ship a browser engine.",
	},
	{
		question: "Does it collect any telemetry?",
		answer:
			"None. No analytics, no crash reporting, no phone-home. There are no network requests beyond cloud transcription when you explicitly enable it.",
	},
	{
		question: "Is there a word or time limit?",
		answer:
			"No word limits and no subscription. Single dictations are capped at 120 seconds as a safety limit.",
	},
	{
		question: "Is TapTalk notarized by Apple?",
		answer:
			"Not yet. It is a solo, open-source project, so on first launch you may need to right-click then Open, or install with Homebrew, which clears the flag for you. The code is fully open, so you can inspect exactly what runs.",
	},
	{
		question: "How do I install it?",
		answer:
			"Run brew install --cask vakharwalad23/tap/taptalk, or download the .dmg from GitHub Releases.",
	},
];
