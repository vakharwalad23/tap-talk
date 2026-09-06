import type { CSSVars } from "#/components/ui/cx";
import { Icon, type IconName } from "#/components/ui/Icon";
import { notList, valueTiles } from "#/content/site";
import styles from "./ValueTiles.module.css";

const icons: readonly IconName[] = ["star", "lock", "bolt", "chip"];

export function ValueTiles() {
	return (
		<section className="section-tight" aria-labelledby="why-title">
			<div className="container">
				<h2 id="why-title" className="sr-only">
					Why TapTalk
				</h2>
				<ul className={styles.grid}>
					{valueTiles.map((tile, index) => {
						const vars: CSSVars = { "--reveal-delay": `${index * 70}ms` };
						return (
							<li
								key={tile.title}
								className={styles.tile}
								data-reveal
								style={vars}
							>
								<span className={styles.icon}>
									<Icon name={icons[index] ?? "check"} size={20} />
								</span>
								<h3>{tile.title}</h3>
								<p>{tile.body}</p>
							</li>
						);
					})}
				</ul>
				<p className={styles.not} data-reveal>
					{notList.map((item) => (
						<span key={item}>{item}</span>
					))}
				</p>
			</div>
		</section>
	);
}
