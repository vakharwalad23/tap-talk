import { privacyStatements } from "#/content/privacy";
import app from "./app.module.css";
import { Checkbox } from "./Checkbox";
import styles from "./SettingsPage.module.css";

interface KeyRowProps {
	readonly label: string;
	readonly keyName: string;
}

function KeyRow({ label, keyName }: KeyRowProps) {
	return (
		<div className={app.row}>
			<span className={app.rowLabel}>{label}</span>
			<span className={styles.keys}>
				<span className={styles.reset}>Reset</span>
				<span className={app.bordered}>{keyName}</span>
			</span>
		</div>
	);
}

export function SettingsPage() {
	return (
		<div>
			<div className={app.header}>
				<h3 className={app.h1}>Settings</h3>
				<p className={app.sub}>Hotkeys, startup and privacy</p>
			</div>

			<section className={app.section}>
				<div className={app.sectionLabel}>Hotkeys</div>
				<div className={app.card}>
					<KeyRow label="Dictation key" keyName="Right Cmd" />
					<div className={app.divider} />
					<KeyRow label="Smart key" keyName="Left Option" />
					<div className={app.divider} />
					<div className={app.row}>
						<span className={app.rowLabel}>Key mode</span>
						<span className={styles.segmented}>
							<span className={styles.selected}>Hold to talk</span>
							<span>Press to toggle</span>
						</span>
					</div>
					<p className={app.hint}>
						Hold the dictation key to type what you say. Esc cancels. The Smart
						key works while Smart Mode is on in Models.
					</p>
				</div>
			</section>

			<section className={app.section}>
				<div className={app.sectionLabel}>Startup</div>
				<div className={app.card}>
					<div className={app.row}>
						<span className={app.rowLabel}>Launch at login</span>
						<Checkbox on />
					</div>
				</div>
			</section>

			<section className={app.section}>
				<div className={app.sectionLabel}>Privacy</div>
				<div className={app.card}>
					<div className={app.row}>
						<span className={app.rowLabel}>Check for updates once a day</span>
						<Checkbox on={false} />
					</div>
					<div className={app.divider} />
					{privacyStatements.map((section) => (
						<div key={section.title} className={styles.statement}>
							<strong>{section.title}</strong>
							<span>{section.body}</span>
						</div>
					))}
				</div>
			</section>
		</div>
	);
}
