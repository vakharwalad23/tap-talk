import { SectionHeading } from "#/components/ui/SectionHeading";
import styles from "./AppReplicas.module.css";
import { AppWindow } from "./AppWindow";
import { IntelligencePage } from "./IntelligencePage";
import { ModelsPage } from "./ModelsPage";
import { PrivacyPage } from "./PrivacyPage";
import { RecordPage } from "./RecordPage";

const tabs = [
	{ id: "record", label: "Record" },
	{ id: "models", label: "Models" },
	{ id: "intelligence", label: "Intelligence" },
	{ id: "privacy", label: "Privacy" },
] as const;

// Tabs are radio inputs styled with CSS so the switcher needs no JavaScript.
export function AppReplicas() {
	return (
		<section className="section" id="inside" aria-labelledby="inside-title">
			<div className="container">
				<SectionHeading
					eyebrow="Inside TapTalk"
					title="The real interface, rebuilt in HTML."
					lede="No screenshots. These are the app's own screens, reproduced from its SwiftUI source with the same colors, sizes, and copy."
					id="inside-title"
				/>
				<div className={styles.tabs} data-reveal>
					{tabs.map((tab, index) => (
						<input
							key={tab.id}
							type="radio"
							name="replica"
							id={`replica-${tab.id}`}
							className={styles.input}
							defaultChecked={index === 0}
						/>
					))}
					<fieldset className={styles.tablist}>
						<legend className="sr-only">App screens</legend>
						{tabs.map((tab) => (
							<label
								key={tab.id}
								htmlFor={`replica-${tab.id}`}
								className={styles.tab}
							>
								{tab.label}
							</label>
						))}
					</fieldset>
					<div className={styles.panels}>
						<div className={styles.panel}>
							<AppWindow active="Record" pill="done">
								<RecordPage />
							</AppWindow>
						</div>
						<div className={styles.panel}>
							<AppWindow active="Models">
								<ModelsPage />
							</AppWindow>
						</div>
						<div className={styles.panel}>
							<AppWindow active="Intelligence" pill="rewriting">
								<IntelligencePage />
							</AppWindow>
						</div>
						<div className={styles.panel}>
							<AppWindow active="Privacy">
								<PrivacyPage />
							</AppWindow>
						</div>
					</div>
				</div>
			</div>
		</section>
	);
}
