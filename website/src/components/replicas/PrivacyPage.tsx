import { privacyPageSections } from "#/content/privacy";
import app from "./app.module.css";
import styles from "./PrivacyPage.module.css";

export function PrivacyPage() {
	return (
		<div>
			<h3 className={app.h1}>Privacy</h3>
			<p className={app.sub}>
				What TapTalk does, and doesn't, do with your data
			</p>
			<div className={styles.sections}>
				{privacyPageSections.map((section) => (
					<div key={section.title} className={styles.section}>
						<div className={app.sectionTitle}>{section.title}</div>
						<p className={app.secondary}>{section.body}</p>
					</div>
				))}
			</div>
		</div>
	);
}
