import {
	formatCount,
	useRepoStats,
} from "#/components/interactive/useRepoStats";
import { ButtonLink } from "#/components/ui/Button";
import { Icon } from "#/components/ui/Icon";
import { Logo } from "#/components/ui/Logo";
import { SectionHeading } from "#/components/ui/SectionHeading";
import { openSource } from "#/content/community";
import { site } from "#/content/site";
import styles from "./OpenSource.module.css";

function Stat({
	label,
	value,
}: {
	readonly label: string;
	readonly value: string;
}) {
	return (
		<span className={styles.stat}>
			<strong>{value}</strong>
			<span>{label}</span>
		</span>
	);
}

export function OpenSource() {
	const stats = useRepoStats(site.repoSlug);
	return (
		<section className="section" id="open-source" aria-labelledby="oss-title">
			<div className="container">
				<SectionHeading
					eyebrow="Open source"
					title={openSource.title}
					lede={openSource.body}
					id="oss-title"
				/>
				<div className={styles.card} data-reveal>
					<div className={styles.repo}>
						<Logo name="github" size={40} />
						<div>
							<a
								href={site.repoUrl}
								target="_blank"
								rel="noopener noreferrer"
								className={styles.slug}
							>
								{site.repoSlug}
							</a>
							<p className="muted">MIT License, macOS, SwiftUI and Rust</p>
						</div>
					</div>
					<div className={styles.stats}>
						<Stat
							label="stars"
							value={stats ? formatCount(stats.stars) : "GitHub"}
						/>
						<Stat
							label="forks"
							value={stats ? formatCount(stats.forks) : "open"}
						/>
						<Stat
							label="open issues"
							value={stats ? formatCount(stats.issues) : "welcome"}
						/>
						<Stat label="latest" value={`v${site.version}`} />
					</div>
					<ul className={styles.actions}>
						{openSource.actions.map((action, index) => (
							<li key={action.title}>
								<span className={styles.actionIcon}>
									<Icon
										name={index === 0 ? "star" : index === 1 ? "fork" : "issue"}
										size={16}
									/>
								</span>
								<div>
									<h3>{action.title}</h3>
									<p>{action.body}</p>
								</div>
							</li>
						))}
					</ul>
					<div className={styles.buttons}>
						<ButtonLink href={site.repoUrl} external>
							<Logo name="github" size={16} />
							View on GitHub
						</ButtonLink>
						<ButtonLink
							href={`${site.repoUrl}/fork`}
							variant="secondary"
							external
						>
							<Icon name="fork" size={16} />
							Fork
						</ButtonLink>
						<ButtonLink href={site.issuesUrl} variant="secondary" external>
							<Icon name="issue" size={16} />
							Open an issue
						</ButtonLink>
					</div>
				</div>
				<p className={styles.maker} data-reveal>
					{openSource.makerNote}
				</p>
			</div>
		</section>
	);
}
