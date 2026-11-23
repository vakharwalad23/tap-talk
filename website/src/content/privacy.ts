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
		body: "No analytics. No crash reporting. Update checks only if you turn them on.",
	},
	{
		title: "No automatic downloads",
		body: "No model is fetched until you choose to download one or to use Cloud.",
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

// Reproduced from the Privacy section of the app's Settings page, with punctuation kept ASCII for the web.
export const privacyStatements = [
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
		title: "Learning from corrections",
		body: "After TapTalk pastes, it reads that text field once, on your next dictation, to see whether you fixed a word it typed. Only the fixed words are kept, on this Mac. Password fields are never read. Turn it off on the Words page.",
	},
	{
		title: "Update checks",
		body: "Off until you say yes. When on, TapTalk asks GitHub once a day for the latest release version. Nothing about you or your Mac is sent beyond what any web request carries.",
	},
	{
		title: "Telemetry",
		body: "None. No analytics, no crash reporting, and no network requests unless you turn on cloud transcription or update checks.",
	},
] as const;
