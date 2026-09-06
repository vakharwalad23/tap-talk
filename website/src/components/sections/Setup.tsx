import { CopyCommand } from "#/components/interactive/CopyCommand";
import { MenuBarMock } from "#/components/replicas/MenuBarMock";
import type { CSSVars } from "#/components/ui/cx";
import { SectionHeading } from "#/components/ui/SectionHeading";
import { setupIntro, setupSteps } from "#/content/setup";
import styles from "./Setup.module.css";

export function Setup() {
	return (
		<section className="section" id="setup" aria-labelledby="setup-title">
			<div className="container">
				<SectionHeading
					eyebrow="Setup"
					title={setupIntro}
					lede="From install to your first pasted sentence, including the two optional extras."
					id="setup-title"
				/>
				<ol className={styles.steps}>
					{setupSteps.map((step, index) => {
						const vars: CSSVars = {
							"--reveal-delay": `${Math.min(index, 3) * 60}ms`,
						};
						return (
							<li
								key={step.title}
								className={styles.step}
								data-reveal
								style={vars}
							>
								<span className={styles.number}>{index + 1}</span>
								<div className={styles.body}>
									<h3>
										{step.title}
										{step.optional ? (
											<span className={styles.optional}>optional</span>
										) : null}
									</h3>
									<p>{step.body}</p>
									{index === 1 ? (
										<div className={styles.mock}>
											<MenuBarMock />
										</div>
									) : null}
									{step.command ? (
										<CopyCommand
											command={step.command}
											className={styles.command}
										/>
									) : null}
									{step.note ? (
										<p className={styles.note}>{step.note}</p>
									) : null}
								</div>
							</li>
						);
					})}
				</ol>
			</div>
		</section>
	);
}
