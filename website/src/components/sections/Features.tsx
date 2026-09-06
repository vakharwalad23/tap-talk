import type { CSSVars } from "#/components/ui/cx";
import { SectionHeading } from "#/components/ui/SectionHeading";
import { featureGroups } from "#/content/features";
import styles from "./Features.module.css";

export function Features() {
	return (
		<section className="section" id="features" aria-labelledby="features-title">
			<div className="container">
				<SectionHeading
					eyebrow="Features"
					title="Everything you need to stop typing. Nothing you have to pay for."
					lede="Every item below is shipped and on in the current release, or one toggle away."
					id="features-title"
				/>
				<div className={styles.groups}>
					{featureGroups.map((group) => (
						<div key={group.title} className={styles.group}>
							<h3 className={styles.groupTitle} data-reveal>
								{group.title}
							</h3>
							<ul className={styles.list}>
								{group.items.map((item, index) => {
									const vars: CSSVars = { "--reveal-delay": `${index * 60}ms` };
									return (
										<li
											key={item.title}
											className={styles.item}
											data-reveal
											style={vars}
										>
											<h4>{item.title}</h4>
											<p>{item.body}</p>
										</li>
									);
								})}
							</ul>
						</div>
					))}
				</div>
			</div>
		</section>
	);
}
