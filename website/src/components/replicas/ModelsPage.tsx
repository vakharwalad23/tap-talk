import { cx } from "#/components/ui/cx";
import { Icon } from "#/components/ui/Icon";
import app from "./app.module.css";
import styles from "./ModelsPage.module.css";

export function ModelsPage() {
	return (
		<div>
			<h3 className={app.h1}>Models</h3>
			<p className={app.sub}>
				Run entirely on your device. No internet required.
			</p>

			<div className={styles.cards}>
				<div className={app.card}>
					<div className={styles.head}>
						<div>
							<div className={styles.name}>Parakeet</div>
							<div className={app.secondary}>
								Fast English and European dictation. Auto-detects the language
								and adds punctuation.
							</div>
						</div>
						<span className={styles.installed}>
							<Icon name="check" size={11} />
							Installed
						</span>
					</div>
					<div className={styles.foot}>
						<span className={app.tertiary}>490 MB, Neural Engine</span>
						<span className={app.ghostButton}>Remove</span>
					</div>
					<div className={styles.addon}>
						<div className={app.rowText}>
							<span className={app.rowTitle}>Live typing add-on</span>
							<span className={app.secondary}>
								Words appear as you speak. 440 MB.
							</span>
						</div>
						<span className={app.smallButton}>Download</span>
					</div>
				</div>

				<div className={app.card}>
					<div className={styles.head}>
						<div>
							<div className={styles.name}>Multilingual</div>
							<div className={app.secondary}>
								Hindi, Marathi, Urdu, Chinese, Japanese and more. Pick the
								language in Record.
							</div>
						</div>
					</div>
					<div className={styles.progress} aria-hidden="true">
						<span className={styles.progressBar} />
					</div>
					<div className={styles.foot}>
						<span className={app.tertiary}>
							Downloading 62 percent of 640 MB
						</span>
						<span className={cx(app.ghostButton)}>Cancel</span>
					</div>
				</div>
			</div>
		</div>
	);
}
