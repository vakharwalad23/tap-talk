import { cx } from "#/components/ui/cx";
import { Logo } from "#/components/ui/Logo";
import { OrukeetMark } from "#/components/ui/OrukeetMark";
import { SectionHeading } from "#/components/ui/SectionHeading";
import { engineComparison as data } from "#/content/engineComparison";
import styles from "./EngineComparison.module.css";

export function EngineComparison() {
	return (
		<section className="section" id="engines" aria-labelledby="engines-title">
			<div className="container">
				<SectionHeading
					eyebrow={data.eyebrow}
					title={data.title}
					lede={data.lede}
					id="engines-title"
				/>
				<div className={styles.scroller} data-reveal>
					<table className={styles.table}>
						<caption className="sr-only">
							Orukeet compared with Parakeet, the two on-device English and
							European engines
						</caption>
						<thead>
							<tr>
								<th scope="col" className={styles.metric}>
									<span className="sr-only">Metric</span>
								</th>
								<th scope="col" className={cx(styles.engine, styles.us)}>
									<a
										href={data.orukeet.url}
										target="_blank"
										rel="noopener noreferrer"
										className={styles.head}
									>
										<span className={styles.mark}>
											<OrukeetMark size={22} label={data.orukeet.name} />
										</span>
										<span className={styles.headText}>
											<strong>{data.orukeet.name}</strong>
											<span className={styles.badge}>
												{data.orukeet.tagline}
											</span>
										</span>
									</a>
								</th>
								<th scope="col" className={styles.engine}>
									<a
										href={data.parakeet.url}
										target="_blank"
										rel="noopener noreferrer"
										className={styles.head}
									>
										<span className={styles.mark}>
											<Logo
												name="nvidia"
												size={22}
												label={data.parakeet.name}
											/>
										</span>
										<span className={styles.headText}>
											<strong>{data.parakeet.name}</strong>
											<span className={styles.tagline}>
												{data.parakeet.tagline}
											</span>
										</span>
									</a>
								</th>
							</tr>
						</thead>
						<tbody>
							{data.rows.map((row) => {
								const orukeetLead =
									row.lead === "orukeet" || row.lead === "tie";
								const parakeetLead =
									row.lead === "parakeet" || row.lead === "tie";
								return (
									<tr key={row.label}>
										<th scope="row" className={styles.metric}>
											<span className={styles.metricInner}>
												<span>{row.label}</span>
												{row.note ? (
													<span className={styles.note}>{row.note}</span>
												) : null}
											</span>
										</th>
										<td
											className={cx(
												styles.value,
												styles.us,
												orukeetLead && styles.lead,
											)}
										>
											{row.orukeet}
										</td>
										<td
											className={cx(styles.value, parakeetLead && styles.lead)}
										>
											{row.parakeet}
										</td>
									</tr>
								);
							})}
						</tbody>
					</table>
				</div>
				<p className={`faint ${styles.footnote}`} data-reveal>
					{data.footnote}
				</p>
			</div>
		</section>
	);
}
