import { cx } from "#/components/ui/cx";
import { Icon } from "#/components/ui/Icon";
import { rewriteModes } from "#/content/intelligence";
import app from "./app.module.css";
import styles from "./IntelligencePage.module.css";

function Checkbox({ on }: { readonly on: boolean }) {
	return (
		<span className={cx(app.checkbox, on && app.checkboxOn)} aria-hidden="true">
			{on ? <Icon name="check" size={10} strokeWidth={3} /> : null}
		</span>
	);
}

const segments = [
	{ name: "Tech", entries: 1 },
	{ name: "Travel", entries: 1 },
] as const;

export function IntelligencePage() {
	return (
		<div>
			<div className={app.header}>
				<h3 className={app.h1}>Intelligence</h3>
				<p className={app.sub}>Dictionary, AI rewriting, and smart hotkey</p>
			</div>

			<section className={app.section}>
				<div className={app.sectionLabel}>Word Dictionary</div>
				<div className={app.card}>
					{segments.map((segment, index) => (
						<div key={segment.name} className={styles.segment}>
							{index > 0 ? <div className={app.divider} /> : null}
							<div className={app.row}>
								<span className={styles.segmentName}>
									<Icon
										name="chevronRight"
										size={10}
										className={app.tertiary}
									/>
									<span>{segment.name}</span>
									<span className={app.hint}>{segment.entries} entries</span>
								</span>
								<span className={styles.segmentActions}>
									<Checkbox on />
									<Icon name="trash" size={11} className={app.danger} />
								</span>
							</div>
						</div>
					))}
					<span className={styles.add}>
						<Icon name="plus" size={11} />
						Add Segment
					</span>
				</div>
			</section>

			<section className={app.section}>
				<div className={app.sectionLabel}>AI Rewriting</div>
				<div className={app.card}>
					<div className={app.row}>
						<span className={app.rowLabel}>Enable AI rewriting</span>
						<Checkbox on />
					</div>
					<div className={app.divider} />
					<div className={app.label}>What the smart hotkey does</div>
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
				</div>
			</section>
		</div>
	);
}
