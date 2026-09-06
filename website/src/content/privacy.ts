export const privacyChecklist = [
	{
		title: "On-device by default",
		body: "Audio captured, trimmed, and transcribed on your Mac.",
	},
	{
		title: "Audio is never saved",
		body: "Processed in memory, then discarded.",
	},
	{
		title: "No account, no telemetry",
		body: "No analytics. No crash reporting. No phone-home.",
	},
	{
		title: "No automatic downloads",
		body: "No model is fetched until you tap Download.",
	},
	{
		title: "Cloud is strictly opt-in",
		body: "OpenAI Whisper only if you choose it and add your own key, stored in the Keychain. Audio then goes to OpenAI, nowhere else.",
	},
	{
		title: "Clipboard-safe",
		body: "Your clipboard is restored after each paste. Dictations never enter clipboard history.",
	},
	{
		title: "Falsifiable",
		body: "It is open source. Do not take our word for it, read the code.",
	},
] as const;

export const permissions = [
	{ name: "Microphone", why: "to capture your voice", when: "first recording" },
	{
		name: "Accessibility",
		why: "to detect the global hotkey and paste",
		when: "first launch",
	},
] as const;

export const permissionsNote =
	"That is it. No full-disk access. No network entitlement needed for on-device engines.";

// Reproduced from the app's Privacy page, with punctuation kept ASCII for the web.
export const privacyPageSections = [
	{
		title: "Data collected",
		body: "None. TapTalk does not collect, store, or transmit any personal data, usage metrics, or crash reports.",
	},
	{
		title: "Microphone",
		body: "Audio is recorded directly from your microphone and processed immediately. No audio files are saved to disk. The recording is discarded after transcription.",
	},
	{
		title: "Local transcription",
		body: "When using the Local engine, transcription runs entirely on your device using models stored in Application Support. Your audio never leaves your Mac.",
	},
	{
		title: "Cloud transcription",
		body: "When using the Cloud engine, audio is sent to OpenAI's Whisper API over HTTPS using your API key. OpenAI's data retention and usage policies apply. Your API key is stored in the macOS Keychain, never in plain text or UserDefaults.",
	},
	{
		title: "Clipboard",
		body: "TapTalk briefly writes transcribed text to the clipboard to paste it into the focused app, then restores the previous clipboard contents. No clipboard data is retained beyond this operation.",
	},
	{
		title: "Telemetry",
		body: "None. No analytics, no crash reporting, no network requests beyond cloud transcription when you explicitly enable it.",
	},
] as const;
