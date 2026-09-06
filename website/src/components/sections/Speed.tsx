import { type CSSVars, cx } from "#/components/ui/cx";
import { SectionHeading } from "#/components/ui/SectionHeading";
import { speed } from "#/content/community";
import styles from "./Speed.module.css";

const maxWer = 35;

export function Speed() {
	return (
		<section className="section" id="speed" aria-labelledby="speed-title">
			<div className="container">
				<SectionHeading
					eyebrow="Speed"
					title={speed.title}
					lede={speed.body}
					id="speed-title"
				/>
				<ul className={styles.stats}>
					{speed.stats.map((stat, index) => {
						const vars: CSSVars = { "--reveal-delay": `${index * 70}ms` };
						return (
							<li
								key={stat.label}
								className={styles.stat}
								data-reveal
								style={vars}
							>
								<span className={styles.value}>{stat.value}</span>
								<span className={styles.label}>{stat.label}</span>
							</li>
						);
					})}
				</ul>
				<div className={styles.chart} data-reveal>
					<h3>{speed.benchmark.title}</h3>
					<ul className={styles.bars}>
						{speed.benchmark.rows.map((row) => {
							const vars: CSSVars = { "--w": `${(row.wer / maxWer) * 100}%` };
							const highlight = "highlight" in row && row.highlight;
							return (
								<li
									key={row.name}
									className={cx(styles.row, highlight && styles.highlight)}
									style={vars}
								>
									<span className={styles.name}>{row.name}</span>
									<span className={styles.track}>
										<span className={styles.bar} />
									</span>
									<span className={styles.wer}>{row.wer}%</span>
								</li>
							);
						})}
					</ul>
					<p className="faint">{speed.benchmark.note}</p>
				</div>
			</div>
		</section>
	);
}
