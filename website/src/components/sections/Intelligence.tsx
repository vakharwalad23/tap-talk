import type { CSSVars } from "#/components/ui/cx";
import { Icon } from "#/components/ui/Icon";
import { SectionHeading } from "#/components/ui/SectionHeading";
import { intelligence, rewriteModes } from "#/content/intelligence";
import styles from "./Intelligence.module.css";

export function Intelligence() {
	return (
		<section
			className="section"
			id="intelligence"
			aria-labelledby="intelligence-title"
		>
			<div className="container">
				<SectionHeading
					eyebrow="Smart Mode"
					title={intelligence.title}
					lede={intelligence.intro}
					id="intelligence-title"
				/>
				<ul className={styles.modes}>
					{rewriteModes.map((mode, index) => {
						const vars: CSSVars = { "--reveal-delay": `${index * 80}ms` };
						return (
							<li
								key={mode.name}
								className={styles.mode}
								data-reveal
								style={vars}
							>
								<div className={styles.head}>
									<h3>{mode.name}</h3>
									<span className={styles.target}>{mode.example.target}</span>
								</div>
								<p className={styles.desc}>{mode.description}</p>
								<div className={styles.example}>
									<p className={styles.raw}>
										<span className={styles.tag}>You say</span>
										{mode.example.raw}
									</p>
									<span className={styles.arrow}>
										<Icon name="arrowRight" size={16} />
									</span>
									<p className={styles.result}>
										<span className={styles.tag}>TapTalk pastes</span>
										{mode.example.target === "Terminal" ? (
											<code>{mode.example.result}</code>
										) : (
											mode.example.result
										)}
									</p>
								</div>
							</li>
						);
					})}
				</ul>
				<div className={styles.notes} data-reveal>
					<p>{intelligence.backends}</p>
					<p className="faint">{intelligence.precedenceNote}</p>
				</div>
			</div>
		</section>
	);
}
