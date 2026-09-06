import { cx } from "#/components/ui/cx";
import { rewriteModes } from "#/content/intelligence";
import app from "./app.module.css";
import styles from "./IntelligencePage.module.css";

function Toggle({ on }: { readonly on: boolean }) {
	return (
		<span className={cx(app.toggle, on && app.toggleOn)} aria-hidden="true" />
	);
}

export function IntelligencePage() {
	return (
		<div className={styles.page}>
			<h3 className={app.h1}>Intelligence</h3>
			<p className={app.sub}>Dictionary, AI rewriting, and smart hotkey</p>

			<section className={styles.block}>
				<div className={app.sectionTitle}>Word Dictionary</div>
				<div className={app.card}>
					<div className={cx(app.row, app.rowFirst)}>
						<div className={app.rowText}>
							<span className={app.rowTitle}>Tech</span>
							<span className={app.secondary}>12 entries</span>
						</div>
						<Toggle on />
					</div>
				</div>
			</section>

			<section className={styles.block}>
				<div className={app.sectionTitle}>AI Rewriting</div>
				<div className={app.card}>
					<div className={cx(app.row, app.rowFirst)}>
						<span className={app.rowTitle}>Enable AI rewriting</span>
						<Toggle on />
					</div>
					{rewriteModes.map((mode) => (
						<div key={mode.name} className={app.row}>
							<div className={app.rowText}>
								<span className={app.rowTitle}>{mode.name}</span>
								<span className={app.secondary}>{mode.description}</span>
							</div>
							<Toggle on />
						</div>
					))}
					<div className={app.row}>
						<div className={app.rowText}>
							<span className={app.rowTitle}>Local (Qwen 2.5 1.5B)</span>
							<span className={app.secondary}>
								<span className={app.dot} />
								Ready, using Metal GPU
							</span>
						</div>
						<span className={app.ghostButton}>Custom Endpoint</span>
					</div>
				</div>
			</section>

			<section className={styles.block}>
				<div className={app.sectionTitle}>Smart Hotkey</div>
				<div className={app.card}>
					<div className={cx(app.row, app.rowFirst)}>
						<div className={app.rowText}>
							<span className={app.rowTitle}>Enable smart hotkey</span>
							<span className={app.secondary}>
								Hold smart key to transcribe plus AI rewrite based on active app
							</span>
						</div>
						<Toggle on />
					</div>
					<div className={app.row}>
						<span className={app.rowTitle}>Smart key</span>
						<span className={app.kbd}>Left Option</span>
					</div>
				</div>
			</section>
		</div>
	);
}
