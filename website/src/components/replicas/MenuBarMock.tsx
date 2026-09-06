import { cx } from "#/components/ui/cx";
import { Icon, type IconName } from "#/components/ui/Icon";
import styles from "./MenuBarMock.module.css";

const before: readonly IconName[] = ["grid", "cloudSlash"];
const after: readonly IconName[] = [
	"playCircle",
	"speaker",
	"battery",
	"wifi",
	"search",
	"sliders",
];

// A macOS menu bar with TapTalk's waveform status item, its dropdown, and a magnified callout.
export function MenuBarMock() {
	return (
		<figure className={styles.wrap} aria-label="TapTalk in the macOS menu bar">
			<div className={styles.bar}>
				<div className={styles.items}>
					{before.map((name) => (
						<Icon key={name} name={name} size={15} className={styles.glyph} />
					))}
					<span className={styles.anchor}>
						<span className={styles.lens} aria-hidden="true">
							<Icon name="waveform" size={38} strokeWidth={2.4} />
						</span>
						<span className={styles.stem} aria-hidden="true" />
						<span className={cx(styles.item, styles.itemOpen)}>
							<Icon
								name="waveform"
								size={15}
								strokeWidth={2.2}
								className={styles.glyph}
							/>
						</span>
						<div className={styles.menu} aria-hidden="true">
							<div className={cx(styles.menuRow, styles.menuRowActive)}>
								<Icon name="window" size={13} />
								Open TapTalk
							</div>
							<div className={styles.menuDivider} />
							<div className={styles.menuRow}>
								<Icon name="power" size={13} />
								Quit TapTalk
							</div>
						</div>
					</span>
					{after.map((name) => (
						<Icon key={name} name={name} size={15} className={styles.glyph} />
					))}
					<span className={styles.clock}>Sun Sep 6 2:29 PM</span>
				</div>
			</div>
			<figcaption className={styles.caption}>
				The waveform in the menu bar is TapTalk. Click it to open the window or
				quit. It turns into a mic badge while you are recording.
			</figcaption>
		</figure>
	);
}
