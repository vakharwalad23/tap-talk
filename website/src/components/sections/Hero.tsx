import { CopyCommand } from "#/components/interactive/CopyCommand";
import { HeroRibbons } from "#/components/interactive/HeroRibbons";
import { StarCount } from "#/components/interactive/StarCount";
import { ButtonLink } from "#/components/ui/Button";
import { Icon } from "#/components/ui/Icon";
import { Logo } from "#/components/ui/Logo";
import { hero, site } from "#/content/site";
import styles from "./Hero.module.css";

export function Hero() {
	return (
		<section className={styles.hero} aria-labelledby="hero-title">
			<div className={`container ${styles.copy}`}>
				<span className="eyebrow">{hero.eyebrow}</span>
				<h1 id="hero-title">{hero.headline}</h1>
				<p className={`lede ${styles.lede}`}>{hero.sub}</p>
				<div className={styles.ctas}>
					<ButtonLink href={site.downloadUrl} size="lg" external>
						<Icon name="download" size={18} />
						Download free
					</ButtonLink>
					<ButtonLink
						href={site.repoUrl}
						variant="secondary"
						size="lg"
						external
					>
						<Logo name="github" size={18} />
						<span>Star on GitHub</span>
						<span className={styles.count}>
							<StarCount repoSlug={site.repoSlug} fallback="MIT" />
						</span>
					</ButtonLink>
				</div>
				<CopyCommand command={site.brewCommand} />
				<p className={styles.requirements}>{site.requirements}</p>
				<p className={styles.note}>
					<Icon name="lock" size={14} />
					<span>
						{hero.makerNote} <a href="#setup">See setup.</a>
					</span>
				</p>
			</div>
			<HeroRibbons />
		</section>
	);
}
