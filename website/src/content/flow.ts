export type FlowLayer = "rust" | "swift";

export interface FlowNode {
	readonly id: string;
	readonly title: string;
	readonly summary: string;
	readonly detail: string;
	readonly layer: FlowLayer;
	readonly optional?: boolean;
}

export const flowCopy = {
	title: "From key-up to pasted text, the whole trip stays on your Mac.",
	intro:
		"When you release the key, TapTalk captures your audio, trims silence, transcribes on the Neural Engine, applies your dictionary and optional AI cleanup, then pastes. It is usually done in under a couple of seconds, entirely on-device.",
	footer:
		"Every box above runs on your Mac. The only way audio leaves is if you switch on the optional cloud engine with your own OpenAI key.",
	liveTypingNote:
		"Live typing takes a different branch: words appear as you speak.",
} as const;

export const flowNodes: readonly FlowNode[] = [
	{
		id: "keydown",
		title: "Key down",
		summary: "prewarm mic and LLM",
		detail:
			"Press your hotkey (default Right Cmd). TapTalk warms the mic instantly. On the Smart key it also spins up the local AI in the background so it is ready by the time you finish.",
		layer: "swift",
	},
	{
		id: "capture",
		title: "Capture",
		summary: "Rust, zero-copy mono",
		detail:
			"A native Rust audio core records from your mic with zero-copy, real-time-safe buffers. No stutters, no allocations while you speak.",
		layer: "rust",
	},
	{
		id: "trim",
		title: "Trim and boost",
		summary: "Silero VAD, AGC, 16 kHz",
		detail:
			"Silero voice-activity detection trims the silence. Automatic gain lifts quiet speech. Resampled to 16 kHz for the model.",
		layer: "rust",
	},
	{
		id: "recognize",
		title: "Recognize",
		summary: "Parakeet or Nemotron on the Neural Engine",
		detail:
			"NVIDIA Parakeet (English and European) or Nemotron (Hindi and more) runs on the Apple Neural Engine via Core ML.",
		layer: "swift",
	},
	{
		id: "dictionary",
		title: "Dictionary",
		summary: "your word replacements",
		detail:
			"Your custom word replacements, names, jargon, shorthand, are applied to every transcript.",
		layer: "swift",
	},
	{
		id: "rewrite",
		title: "Rewrite",
		summary: "local LLM matches the app",
		detail:
			"A local LLM polishes filler, resolves 'no wait, I meant' corrections, and reformats to fit the app you are in. On-device by default.",
		layer: "swift",
		optional: true,
	},
	{
		id: "paste",
		title: "Paste",
		summary: "clipboard-safe",
		detail:
			"Text is pasted into the focused field, your previous clipboard is restored, and the entry is marked so clipboard managers skip it.",
		layer: "swift",
	},
];
