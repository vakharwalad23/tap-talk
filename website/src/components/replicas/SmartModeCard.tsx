import { cx } from "#/components/ui/cx";
import { Icon } from "#/components/ui/Icon";
import { rewriteModes } from "#/content/intelligence";
import app from "./app.module.css";
import { Checkbox } from "./Checkbox";
import styles from "./SmartModeCard.module.css";

export function SmartModeCard() {
	return (
		<div className={app.card}>
			<div className={app.row}>
				<span className={styles.name}>Smart Mode</span>
				<Checkbox on />
			</div>
			<p className={app.hint}>
				Rewrites what you dictate with an AI model, on this Mac or at a server
				you choose.
			</p>
			<div className={app.divider} />
			<div className={app.label}>What the Smart key does</div>
			{rewriteModes.map((mode) => (
				<div key={mode.name} className={cx(app.row, app.rowTop)}>
					<div className={app.rowText}>
						<span className={app.rowTitle}>{mode.name}</span>
						<span className={app.hintSmall}>{mode.description}</span>
					</div>
					<Checkbox on={mode.name !== "Match the app"} />
				</div>
			))}
			<div className={app.divider} />
			<div className={app.tiles}>
				<span className={app.tile}>
					<strong>Custom Endpoint</strong>
					<span>Ollama, LM Studio, OpenAI</span>
				</span>
				<span className={cx(app.tile, app.tileActive)}>
					<strong>Local (Qwen)</strong>
					<span>On-device, private</span>
				</span>
			</div>
			<div className={app.divider} />
			<div className={cx(app.row, app.rowTop)}>
				<div className={app.rowText}>
					<span className={app.rowTitle}>Local Intelligence</span>
					<span className={app.hint}>
						On-device - running locally with Metal GPU
					</span>
				</div>
				<span className={styles.remove}>
					<Icon
						name="checkCircle"
						size={13}
						strokeWidth={2.2}
						className={app.ok}
					/>
					Remove
				</span>
			</div>
			<span className={cx(app.installed, styles.ready)}>
				<Icon name="checkCircle" size={13} strokeWidth={2.2} />
				Ready - using Metal GPU
			</span>
			<div className={app.divider} />
			<span className={cx(app.secondary, styles.ready)}>
				Hold Left Option to rewrite. Change the key in Settings.
			</span>
		</div>
	);
}
