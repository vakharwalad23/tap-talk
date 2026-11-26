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
		body: "The Record page opens with a setup card. Click Download on it to fetch Orukeet (about 467 MB), the recommended engine for English and European languages. It is selected as your engine automatically, so you can dictate as soon as it finishes. Want Parakeet (about 490 MB), or Nemotron (about 640 MB) for Hindi and more? Download it on the Models page and it becomes your engine when the download finishes; Use on any installed model switches back. Downloads land in Application Support and keep going even if you navigate away. Nothing is bundled.",
	},
	{
		title: "Grant two permissions",
		body: "The same card has an Allow button for Microphone (to hear you) and one for Accessibility (to detect the global hotkey and paste). Nothing is asked before you click. No full-disk access, no network permission for on-device use.",
		note: "If the card asks for a restart after you allow Accessibility, click Restart TapTalk. Releases are signed with the same certificate, so updates keep both permissions. The first update from a version before that change asks once more: open TapTalk and click Allow on the setup card.",
	},
	{
		title: "Dictate",
		body: "Put your cursor anywhere you can type, hold Right Cmd, speak, and release. Your words are transcribed on the Neural Engine and pasted in. Watch the pill: a red timer and live bars while it listens, then a green Pasted tick. Esc or the cross cancels. Rather not hold the key? In Settings, set Key mode to Press to toggle: press once to start and again to finish.",
	},
	{
		title: "Turn on Smart Mode",
		optional: true,
		body: "On the Models page, switch on Smart Mode, pick Local (Qwen), and Download the on-device model (Qwen 2.5, about 1.06 GB, plus a small llama.cpp server fetched on first use). Turn on the modes you want. Now use the Smart key (Left Option, change it in Settings) instead of the dictation key to transcribe and rewrite. Prefer your own model? Choose Custom Endpoint and point it at Ollama, LM Studio, or OpenAI.",
	},
	{
		title: "Turn on Live typing",
		optional: true,
		body: "Live typing works with Parakeet only, not with Orukeet, Nemotron or Cloud. For words that appear as you speak, click Use on Parakeet in Models, download its Live typing add-on, and turn on the Live typing switch that appears on the Parakeet card.",
	},
];
