import type { CSSVars } from "#/components/ui/cx";
import { Icon } from "#/components/ui/Icon";
import { Logo } from "#/components/ui/Logo";
import { SectionHeading } from "#/components/ui/SectionHeading";
import { tech } from "#/content/community";
import {
	builtWith,
	type LogoEntry,
	logosDisclaimer,
	models,
} from "#/content/logos";
import styles from "./Tech.module.css";

function LogoCard({ entry }: { readonly entry: LogoEntry }) {
	return (
		<li>
			<a
				href={entry.url}
				target="_blank"
				rel="noopener noreferrer"
				className={styles.logo}
			>
				<span className={styles.mark}>
					{entry.logo ? (
						<Logo name={entry.logo} size={22} label={entry.name} />
					) : (
						<Icon name={entry.icon ?? "chip"} size={22} />
					)}
				</span>
				<span className={styles.logoText}>
					<strong>{entry.name}</strong>
					{entry.role ? <span>{entry.role}</span> : null}
					{entry.license ? (
						<span className={styles.license}>{entry.license}</span>
					) : null}
				</span>
			</a>
		</li>
	);
}

export function Tech() {
	return (
		<section className="section" id="tech" aria-labelledby="tech-title">
			<div className="container">
				<SectionHeading
					eyebrow="Under the hood"
					title={tech.title}
					id="tech-title"
				/>
				<ul className={styles.items}>
					{tech.items.map((item, index) => {
						const vars: CSSVars = { "--reveal-delay": `${index * 60}ms` };
						return (
							<li
								key={item.title}
								className={styles.item}
								data-reveal
								style={vars}
							>
								<h3>{item.title}</h3>
								<p>{item.body}</p>
							</li>
						);
					})}
				</ul>
				<div className={styles.strip} data-reveal>
					<h3>Built with</h3>
					<ul className={styles.logos}>
						{builtWith.map((entry) => (
							<LogoCard key={entry.name} entry={entry} />
						))}
					</ul>
				</div>
				<div className={styles.strip} data-reveal>
					<h3>Powered by these models</h3>
					<ul className={styles.logos}>
						{models.map((entry) => (
							<LogoCard key={entry.name} entry={entry} />
						))}
					</ul>
				</div>
				<p className={`faint ${styles.disclaimer}`} data-reveal>
					{logosDisclaimer}
				</p>
			</div>
		</section>
	);
}
