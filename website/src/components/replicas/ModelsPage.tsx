import { cx } from "#/components/ui/cx";
import { Icon } from "#/components/ui/Icon";
import app from "./app.module.css";
import styles from "./ModelsPage.module.css";

function Installed() {
	return (
		<span className={styles.actions}>
			<span className={app.installed}>
				<Icon name="checkCircle" size={13} strokeWidth={2.2} />
				Installed
			</span>
			<Icon name="trash" size={11} className={app.danger} />
		</span>
	);
}

export function ModelsPage() {
	return (
		<div>
			<div className={app.header}>
				<h3 className={app.h1}>Models</h3>
				<p className={app.sub}>
					Run entirely on your device - no internet required.
				</p>
			</div>

			<div className={styles.cards}>
				<div className={app.card}>
					<div className={app.row}>
						<span className={styles.nameRow}>
							<span className={styles.name}>Parakeet TDT</span>
							<span className={app.badge}>Optimized</span>
						</span>
						<span className={app.size}>~490 MB</span>
					</div>
					<div className={cx(app.row, styles.descRow)}>
						<p className={cx(app.hint, styles.desc)}>
							NVIDIA Parakeet TDT 0.6B v3. The fastest option for English and
							European languages. Adds punctuation for you.
						</p>
						<Installed />
					</div>
					<div className={app.divider} />
					<div className={cx(app.row, app.rowTop)}>
						<div className={app.rowText}>
							<span className={styles.nameRow}>
								<span className={app.rowTitle}>Live typing add-on</span>
								<span className={cx(app.size, styles.sizeSmall)}>~440 MB</span>
							</span>
							<span className={app.hint}>
								Streams words live as you speak. Required for the Live typing
								toggle in Settings.
							</span>
						</div>
						<span className={styles.actions}>
							<Icon
								name="checkCircle"
								size={13}
								strokeWidth={2.2}
								className={app.ok}
							/>
							<Icon name="trash" size={11} className={app.danger} />
						</span>
					</div>
				</div>

				<div className={app.card}>
					<div className={app.row}>
						<span className={styles.name}>Nemotron 3.5</span>
						<span className={app.size}>~640 MB</span>
					</div>
					<div className={cx(app.row, styles.descRow)}>
						<p className={cx(app.hint, styles.desc)}>
							NVIDIA Nemotron 3.5 ASR. Covers Hindi and the languages Parakeet
							doesn't - pick yours in the Record tab.
						</p>
						<span className={app.downloadButton}>Download</span>
					</div>
				</div>
			</div>
		</div>
	);
}
