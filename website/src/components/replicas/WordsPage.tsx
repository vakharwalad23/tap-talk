import { Icon } from "#/components/ui/Icon";
import app from "./app.module.css";
import { Checkbox } from "./Checkbox";
import styles from "./WordsPage.module.css";

const segments = [
	{ name: "Tech", entries: 1 },
	{ name: "Travel", entries: 1 },
] as const;

export function WordsPage() {
	return (
		<div>
			<div className={app.header}>
				<h3 className={app.h1}>Words</h3>
				<p className={app.sub}>Words TapTalk replaces after transcribing</p>
			</div>

			<section className={app.section}>
				<div className={app.sectionLabel}>Word Dictionary</div>
				<div className={app.card}>
					{segments.map((segment, index) => (
						<div key={segment.name} className={styles.segment}>
							{index > 0 ? <div className={app.divider} /> : null}
							<div className={app.row}>
								<span className={styles.segmentName}>
									<Icon
										name="chevronRight"
										size={10}
										className={app.tertiary}
									/>
									<span>{segment.name}</span>
									<span className={app.hint}>{segment.entries} entries</span>
								</span>
								<span className={styles.segmentActions}>
									<Checkbox on />
									<Icon name="trash" size={11} className={app.danger} />
								</span>
							</div>
						</div>
					))}
					<span className={styles.add}>
						<Icon name="plus" size={11} />
						Add Segment
					</span>
				</div>
			</section>
		</div>
	);
}
