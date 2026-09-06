import { Icon } from "#/components/ui/Icon";
import { site } from "#/content/site";
import styles from "./AboutPage.module.css";
import app from "./app.module.css";

// Copy from the app's About page, with punctuation kept ASCII for the web.
const rows = [
	{ label: "Engines", value: "NVIDIA Parakeet TDT, Nemotron 3.5 ASR" },
	{ label: "Runtime", value: "Core ML / Neural Engine via FluidAudio" },
	{ label: "Rewrite", value: "Qwen 2.5 1.5B, llama.cpp" },
	{ label: "Audio", value: "cpal, Silero VAD silence trimming" },
	{ label: "Platform", value: "macOS 14+, Apple Silicon" },
] as const;

export function AboutPage() {
	return (
		<div className={styles.page}>
			<div className={app.header}>
				<h3 className={app.h1}>About</h3>
			</div>
			<div>
				<div className={styles.name}>TapTalk</div>
				<div className={app.secondary}>Version {site.version} (3)</div>
			</div>
			<p className={styles.blurb}>
				Local speech-to-text for macOS. Hold a hotkey, speak, release, and your
				words appear wherever the cursor is. Speak English, Hindi, or a hundred
				other languages, and let a local model clean up the transcript before it
				lands. Runs entirely on-device on the Neural Engine. No account, no
				cloud by default.
			</p>
			<div className={app.divider} />
			<dl className={styles.rows}>
				{rows.map((row) => (
					<div key={row.label} className={styles.row}>
						<dt className={app.tertiary}>{row.label}</dt>
						<dd className={app.secondary}>{row.value}</dd>
					</div>
				))}
			</dl>
			<div className={app.divider} />
			<span className={styles.link}>
				View on GitHub
				<Icon name="arrowUpRight" size={9} strokeWidth={2.6} />
			</span>
		</div>
	);
}
