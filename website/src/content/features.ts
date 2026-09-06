export interface Feature {
	readonly title: string;
	readonly body: string;
}

export interface FeatureGroup {
	readonly title: string;
	readonly items: readonly Feature[];
}

export const featureGroups: readonly FeatureGroup[] = [
	{
		title: "Dictation",
		items: [
			{
				title: "Global push-to-talk",
				body: "Hold a hotkey anywhere in macOS, even with every window closed. Rebindable, default Right Cmd.",
			},
			{
				title: "Paste into any app",
				body: "Slack, Mail, Notion, Xcode, the terminal, your browser. Text lands where the cursor is, with a flicker-free accessibility path and a universal paste fallback that works in Electron apps too.",
			},
			{
				title: "Live typing (optional)",
				body: "Watch words appear in the field as you speak, under a second, with a confirmed plus volatile preview. Streams locally.",
			},
			{
				title: "Too short? It says so",
				body: "Tap the key by accident and TapTalk tells you to hold longer. It never invents a transcript from silence.",
			},
		],
	},
	{
		title: "On-device intelligence",
		items: [
			{
				title: "Smart Mode",
				body: "A separate Smart hotkey transcribes and rewrites, locally. Three composable modes: Polish, Restructure, Match the app.",
			},
			{
				title: "Context-aware",
				body: "It reads which app, and even which window, you are dictating into and matches the tone. A shell command in Terminal, a casual line in Slack, clean prose in Notes.",
			},
			{
				title: "Custom dictionary",
				body: "Teach it your names, jargon, and shorthand. Applied to every transcription, before any AI.",
			},
		],
	},
	{
		title: "Languages",
		items: [
			{
				title: "English and European",
				body: "NVIDIA Parakeet, auto-detected, punctuation included.",
			},
			{
				title: "Hindi, Marathi, Urdu, Chinese, Japanese, and more",
				body: "NVIDIA Nemotron, with an honest language picker that only offers what the model can actually produce.",
			},
			{
				title: "Hinglish romanization",
				body: "Speak Hindi, get natural Roman-script Hinglish, with English loanwords kept in English. Unique on-device.",
			},
		],
	},
	{
		title: "Privacy and control",
		items: [
			{
				title: "On-device by default",
				body: "No account, no telemetry, no network calls unless you turn on cloud.",
			},
			{
				title: "Audio is never saved",
				body: "Processed in memory, discarded after transcription.",
			},
			{
				title: "Clipboard-safe",
				body: "Your clipboard is restored after every paste. Dictations never enter clipboard history.",
			},
			{
				title: "Optional cloud, your key",
				body: "OpenAI Whisper is available if you want it. Off by default, your own API key, stored in the macOS Keychain.",
			},
		],
	},
	{
		title: "Craft and performance",
		items: [
			{
				title: "Neural Engine acceleration",
				body: "Core ML models run on the Apple Neural Engine, not the CPU.",
			},
			{
				title: "Native SwiftUI plus Rust",
				body: "No Electron. No bundled model bloat. Models download only when you ask.",
			},
			{
				title: "Light on your Mac",
				body: "About 164 MB resident with a model loaded, since weights are memory-mapped. Models auto-release under memory pressure or after idle.",
			},
			{
				title: "A hotkey that does not die",
				body: "Self-heals from macOS event-tap failure modes and survives sleep and wake.",
			},
		],
	},
];
