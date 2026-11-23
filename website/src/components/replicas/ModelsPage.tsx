import { cx } from "#/components/ui/cx";
import { Icon } from "#/components/ui/Icon";
import app from "./app.module.css";
import styles from "./ModelsPage.module.css";
import { SmartModeCard } from "./SmartModeCard";

function InUse() {
	return (
		<span className={styles.actions}>
			<span className={app.installed}>
				<Icon name="checkCircle" size={13} strokeWidth={2.2} />
				In use
			</span>
			<Icon name="trash" size={11} className={app.danger} />
		</span>
	);
}

function Use() {
	return (
		<span className={styles.actions}>
			<span className={app.downloadButton}>Use</span>
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
					Speech and Smart Mode. Runs on this Mac unless you choose Cloud or a
					Smart Mode server
				</p>
			</div>

			<div className={styles.cards}>
				<div className={styles.group}>Speech</div>
				<div className={app.card}>
					<div className={app.row}>
						<span className={styles.nameRow}>
							<span className={styles.name}>Orukeet</span>
							<span className={app.badgeGood}>More accurate</span>
							<span className={app.badgeMuted}>Fast</span>
						</span>
						<span className={app.size}>~467 MB</span>
					</div>
					<div className={cx(app.row, styles.descRow)}>
						<p className={cx(app.hint, styles.desc)}>
							Orukeet r3. Makes fewer mistakes than Parakeet. English and 24
							European languages.
						</p>
						<InUse />
					</div>
				</div>

				<div className={app.card}>
					<div className={app.row}>
						<span className={styles.nameRow}>
							<span className={styles.name}>Parakeet TDT</span>
							<span className={app.badgeMuted}>Fast</span>
						</span>
						<span className={app.size}>~490 MB</span>
					</div>
					<div className={cx(app.row, styles.descRow)}>
						<p className={cx(app.hint, styles.desc)}>
							NVIDIA Parakeet TDT 0.6B v3. Fast English and European dictation.
							Adds punctuation for you.
						</p>
						<Use />
					</div>
					<div className={app.divider} />
					<div className={cx(app.row, app.rowTop)}>
						<div className={app.rowText}>
							<span className={styles.nameRow}>
								<span className={app.rowTitle}>Live typing add-on</span>
								<span className={cx(app.size, styles.sizeSmall)}>~440 MB</span>
							</span>
							<span className={app.hint}>
								Streams words live as you speak. Its switch appears here while
								Parakeet is in use.
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

				<div className={app.card}>
					<div className={app.row}>
						<span className={styles.name}>Cloud - OpenAI Whisper</span>
						<span className={cx(app.downloadButton, styles.disabled)}>Use</span>
					</div>
					<p className={app.hint}>
						Sends your audio to OpenAI with your own API key. Needs an internet
						connection.
					</p>
					<div className={app.divider} />
					<div className={app.label}>OpenAI API key</div>
					<div className={styles.keyRow}>
						<span className={styles.keyField}>sk-...</span>
						<span className={app.bordered}>Save</span>
					</div>
				</div>

				<div className={styles.group}>Smart Mode</div>
				<SmartModeCard />
			</div>
		</div>
	);
}
