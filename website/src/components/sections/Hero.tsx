import { CopyCommand } from "#/components/interactive/CopyCommand";
import { Pill } from "#/components/interactive/Pill";
import { StarCount } from "#/components/interactive/StarCount";
import { TypedDemo } from "#/components/interactive/TypedDemo";
import { ButtonLink } from "#/components/ui/Button";
import { Icon } from "#/components/ui/Icon";
import { Logo } from "#/components/ui/Logo";
import { hero, site } from "#/content/site";
import styles from "./Hero.module.css";

export function Hero() {
	return (
		<section className={styles.hero} aria-labelledby="hero-title">
			<div className={`container ${styles.grid}`}>
				<div className={styles.copy}>
					<span className="eyebrow">{hero.eyebrow}</span>
					<h1 id="hero-title">{hero.headline}</h1>
					<p className="lede">{hero.sub}</p>
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
							<span>
								Star on GitHub,{" "}
								<StarCount repoSlug={site.repoSlug} fallback="open source" />
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
				<div className={styles.visual}>
					<TypedDemo
						raw={hero.demo.raw}
						clean={hero.demo.clean}
						caption={hero.demo.caption}
					/>
					<div className={styles.pill}>
						<Pill state="recording" />
					</div>
				</div>
			</div>
		</section>
	);
}
