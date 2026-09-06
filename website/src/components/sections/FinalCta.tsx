import { CopyCommand } from "#/components/interactive/CopyCommand";
import { ButtonLink } from "#/components/ui/Button";
import { Icon } from "#/components/ui/Icon";
import { Logo } from "#/components/ui/Logo";
import { finalCta } from "#/content/community";
import { site } from "#/content/site";
import styles from "./FinalCta.module.css";

export function FinalCta() {
	return (
		<section className="section" aria-labelledby="cta-title">
			<div className="container">
				<div className={styles.band} data-reveal>
					<h2 id="cta-title">{finalCta.title}</h2>
					<p>{finalCta.body}</p>
					<div className={styles.buttons}>
						<ButtonLink
							href={site.downloadUrl}
							size="lg"
							className={styles.primary}
						>
							<Icon name="download" size={18} />
							Download free
						</ButtonLink>
						<ButtonLink
							href={site.repoUrl}
							size="lg"
							external
							className={styles.secondary}
						>
							<Logo name="github" size={18} />
							Star on GitHub
						</ButtonLink>
					</div>
					<CopyCommand command={site.brewCommand} className={styles.command} />
					<p className={styles.requirements}>{site.requirements}</p>
				</div>
			</div>
		</section>
	);
}
