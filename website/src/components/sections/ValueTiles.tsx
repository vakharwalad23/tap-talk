import type { CSSVars } from "#/components/ui/cx";
import { notList, valueTiles } from "#/content/site";
import styles from "./ValueTiles.module.css";

export function ValueTiles() {
	return (
		<section className="section-tight" aria-labelledby="why-title">
			<div className="container">
				<h2 id="why-title" className="sr-only">
					Why TapTalk
				</h2>
				<ol className={styles.grid}>
					{valueTiles.map((tile, index) => {
						const vars: CSSVars = { "--reveal-delay": `${index * 70}ms` };
						return (
							<li
								key={tile.title}
								className={styles.item}
								data-reveal
								style={vars}
							>
								<span className={styles.index}>0{index + 1}</span>
								<h3>{tile.title}</h3>
								<p>{tile.body}</p>
							</li>
						);
					})}
				</ol>
				<p className={styles.not} data-reveal>
					{notList.map((item, index) => (
						<span key={item}>
							{index > 0 ? <span aria-hidden="true">/</span> : null}
							{item}
						</span>
					))}
				</p>
			</div>
		</section>
	);
}
