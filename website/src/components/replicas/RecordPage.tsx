import { cx } from "#/components/ui/cx";
import { Icon } from "#/components/ui/Icon";
import { hero } from "#/content/site";
import app from "./app.module.css";
import styles from "./RecordPage.module.css";

const BAR_COUNT = 20;
const bars = Array.from({ length: BAR_COUNT }, (_, index) => index);

export function RecordPage() {
	return (
		<div className={styles.page}>
			<div className={styles.chips}>
				<span className={app.chip}>
					<Icon name="bolt" size={10} />
					Parakeet
				</span>
				<span className={cx(app.chip, app.chipMuted)}>
					<Icon name="globe" size={10} />
					Auto
				</span>
			</div>

			<div className={styles.waveform} aria-hidden="true">
				{bars.map((index) => (
					<span key={index} className={styles.bar} />
				))}
			</div>
			<p className={cx(styles.status, app.secondary)}>Ready</p>

			<div className={styles.transcript}>
				<p>{hero.demo.clean}</p>
				<div className={styles.meta}>
					<span>
						<Icon name="globe" size={10} /> en
					</span>
					<span>172 ms</span>
					<span>3.2 s</span>
					<span className={styles.copy}>Copy</span>
				</div>
			</div>

			<div className={styles.bottom}>
				<span className={app.primaryButton}>
					<Icon name="mic" size={15} />
					Record
				</span>
				<p className={styles.hotkey}>
					<Icon name="keyboard" size={10} />
					Hotkey active, Right Cmd
				</p>
			</div>
		</div>
	);
}
