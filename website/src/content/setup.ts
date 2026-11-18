export interface SetupStep {
	readonly title: string;
	readonly body: string;
	readonly command?: string;
	readonly note?: string;
	readonly optional?: boolean;
}

export const setupIntro = "Up and running in about two minutes.";

export const setupSteps: readonly SetupStep[] = [
	{
		title: "Install",
		body: "Homebrew is the easy path. The cask downloads the app and clears the Gatekeeper quarantine flag for you, so it opens on the first try. Or download the .dmg from GitHub Releases and drag TapTalk to Applications.",
		command: "brew install --cask vakharwalad23/tap/taptalk",
		note: "TapTalk is not notarized yet (it is a solo, open-source project). If macOS says the app is damaged, right-click then Open, or run: xattr -dr com.apple.quarantine /Applications/TapTalk.app",
	},
	{
		title: "Open it from the menu bar",
		body: "TapTalk lives in your menu bar, not the Dock. Click the TapTalk icon at the top, then Open TapTalk.",
	},
	{
		title: "Download a model",
		body: "Go to the Models tab. Tap Download on Orukeet (about 467 MB, the recommended default for English and European), Parakeet (about 490 MB), or Nemotron (about 640 MB) for Hindi and more. The model you download is selected as your engine automatically, so you can dictate right away; switch between installed engines any time in Settings. Downloads land in Application Support and keep going even if you navigate away. Nothing is bundled.",
	},
	{
		title: "Grant two permissions",
		body: "On first use TapTalk asks for Microphone (to hear you) and Accessibility (to detect the global hotkey and paste). That is it. No full-disk access, no network permission for on-device use.",
		note: "If the hotkey does not fire right after you grant Accessibility, quit and reopen once. TapTalk is not notarized yet, so a new version can look like a different app to macOS and may ask for these permissions again. If the hotkey stays dead after an update, remove the old TapTalk entry under System Settings, Privacy and Security, Accessibility, relaunch TapTalk, and grant it again.",
	},
	{
		title: "Dictate",
		body: "Put your cursor anywhere you can type, hold Right Cmd, speak, and release. Your words are transcribed on the Neural Engine and pasted in. Watch the pill: red while listening, then green Pasted when it is done.",
	},
	{
		title: "Turn on Intelligence",
		optional: true,
		body: "Open Intelligence, enable AI rewriting, pick Local, and Download the on-device model (Qwen 2.5, about 1.06 GB, plus a small llama.cpp server fetched on first use). Turn on the modes you want and enable the Smart hotkey (default Left Option). Now hold the Smart key to transcribe and rewrite. Prefer your own model? Choose Custom Endpoint and point it at Ollama, LM Studio, or OpenAI.",
	},
	{
		title: "Turn on Live typing (coming soon)",
		optional: true,
		body: "For words that appear as you speak, keep Parakeet selected, install the Live typing add-on from Models, and turn on the toggle in Settings.",
	},
];
