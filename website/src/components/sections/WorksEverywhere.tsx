import type { CSSVars } from "#/components/ui/cx";
import { Icon } from "#/components/ui/Icon";
import { Logo } from "#/components/ui/Logo";
import { SectionHeading } from "#/components/ui/SectionHeading";
import { apps, appsCopy } from "#/content/apps";
import styles from "./WorksEverywhere.module.css";

export function WorksEverywhere() {
	return (
		<section className="section-tight" id="apps" aria-labelledby="apps-title">
			<div className="container">
				<SectionHeading
					title={appsCopy.title}
					lede={appsCopy.body}
					align="center"
					id="apps-title"
				/>
				<ul className={styles.row}>
					{apps.map((app, index) => {
						const vars: CSSVars = { "--reveal-delay": `${index * 40}ms` };
						return (
							<li
								key={app.name}
								className={styles.app}
								data-reveal
								style={vars}
							>
								{app.logo ? (
									<Logo name={app.logo} size={22} label={app.name} />
								) : null}
								{app.glyph ? <Icon name={app.glyph} size={22} /> : null}
								<span>{app.name}</span>
							</li>
						);
					})}
				</ul>
			</div>
		</section>
	);
}
