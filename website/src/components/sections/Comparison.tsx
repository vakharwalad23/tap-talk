import { cx } from "#/components/ui/cx";
import { Icon, type IconName } from "#/components/ui/Icon";
import { SectionHeading } from "#/components/ui/SectionHeading";
import {
	type Cell,
	comparisonCallouts,
	comparisonCriteria,
	comparisonIntro,
	comparisonSourcesNote,
	rivals,
	taptalkRow,
} from "#/content/comparison";
import styles from "./Comparison.module.css";

const products = [taptalkRow, ...rivals];

const verdictIcon: Record<Cell["verdict"], IconName> = {
	yes: "check",
	no: "x",
	partial: "minus",
};
const verdictLabel: Record<Cell["verdict"], string> = {
	yes: "Yes",
	no: "No",
	partial: "Partial",
};

function CellView({ cell }: { readonly cell: Cell }) {
	return (
		<span className={cx(styles.cell, styles[cell.verdict])}>
			<Icon
				name={verdictIcon[cell.verdict]}
				size={16}
				title={verdictLabel[cell.verdict]}
			/>
			{cell.note ? <small>{cell.note}</small> : null}
		</span>
	);
}

export function Comparison() {
	return (
		<section className="section" id="compare" aria-labelledby="compare-title">
			<div className="container">
				<SectionHeading
					eyebrow="Compared"
					title="How TapTalk compares."
					lede={comparisonIntro}
					id="compare-title"
				/>
				<div className={styles.scroller} data-reveal>
					<table className={styles.table}>
						<caption className="sr-only">
							TapTalk compared with other Mac dictation apps
						</caption>
						<thead>
							<tr>
								<th scope="col" className={styles.criteria}>
									<span className="sr-only">Criteria</span>
								</th>
								{products.map((product) => (
									<th
										key={product.name}
										scope="col"
										className={cx(product === taptalkRow && styles.us)}
									>
										<a
											href={product.url}
											target="_blank"
											rel="noopener noreferrer"
										>
											{product.name}
										</a>
									</th>
								))}
							</tr>
						</thead>
						<tbody>
							<tr>
								<th scope="row" className={styles.criteria}>
									Price
								</th>
								{products.map((product) => (
									<td
										key={product.name}
										className={cx(
											styles.text,
											product === taptalkRow && styles.us,
										)}
									>
										{product.price}
									</td>
								))}
							</tr>
							{comparisonCriteria.map((criterion, index) => (
								<tr key={criterion}>
									<th scope="row" className={styles.criteria}>
										{criterion}
									</th>
									{products.map((product) => {
										const cell = product.cells[index];
										return (
											<td
												key={product.name}
												className={cx(product === taptalkRow && styles.us)}
											>
												{cell ? <CellView cell={cell} /> : null}
											</td>
										);
									})}
								</tr>
							))}
							<tr>
								<th scope="row" className={styles.criteria}>
									Platforms
								</th>
								{products.map((product) => (
									<td
										key={product.name}
										className={cx(
											styles.text,
											product === taptalkRow && styles.us,
										)}
									>
										{product.platforms}
									</td>
								))}
							</tr>
						</tbody>
					</table>
				</div>
				<ul className={styles.callouts}>
					{comparisonCallouts.map((callout) => (
						<li key={callout.versus} className={styles.callout} data-reveal>
							<h3>vs {callout.versus}</h3>
							<p>{callout.text}</p>
						</li>
					))}
				</ul>
				<p className={`faint ${styles.sources}`} data-reveal>
					{comparisonSourcesNote}
				</p>
			</div>
		</section>
	);
}
