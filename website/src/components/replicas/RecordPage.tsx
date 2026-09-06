import { cx } from "#/components/ui/cx";
import { Icon } from "#/components/ui/Icon";
import { hero } from "#/content/site";
import app from "./app.module.css";
import styles from "./RecordPage.module.css";

const bars = Array.from({ length: 20 }, (_, index) => `bar-${index}`);

export function RecordPage() {
	return (
		<div className={styles.page}>
			<div className={styles.chips}>
				<span className={cx(app.chip, styles.engineChip)}>
					<Icon name="bolt" size={10} />
					Parakeet TDT
				</span>
				<span className={cx(app.chip, styles.langChip)}>
					<Icon name="globe" size={10} />
					Auto - EU
				</span>
			</div>

			<div className={styles.waveform} aria-hidden="true">
				{bars.map((id) => (
					<span key={id} className={styles.bar} />
				))}
			</div>
			<p className={styles.status}>Done</p>

			<div className={styles.transcript}>
				<p>{hero.demo.clean}</p>
				<div className={styles.meta}>
					<span>
						<Icon name="globe" size={10} />
						AUTO
					</span>
					<span>
						<Icon name="timer" size={10} />
						122ms
					</span>
					<span>
						<Icon name="waveform" size={10} />
						3.2s audio
					</span>
					<span className={styles.copy}>
						<Icon name="copy" size={10} />
						Copy
					</span>
				</div>
			</div>

			<div className={styles.bottom}>
				<span className={app.primaryButton}>
					<Icon name="mic" size={15} strokeWidth={2.4} />
					Record
				</span>
				<p className={styles.hotkey}>
					<Icon name="keyboard" size={10} />
					Hotkey active - Right Cmd
				</p>
			</div>
		</div>
	);
}
