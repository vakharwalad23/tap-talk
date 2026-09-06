import { StarCount } from "#/components/interactive/StarCount";
import { ButtonLink } from "#/components/ui/Button";
import { Logo } from "#/components/ui/Logo";
import { site } from "#/content/site";
import styles from "./Nav.module.css";

const links = [
	{ href: "#how", label: "How it works" },
	{ href: "#features", label: "Features" },
	{ href: "#intelligence", label: "Intelligence" },
	{ href: "#compare", label: "Compare" },
	{ href: "#setup", label: "Setup" },
	{ href: "#faq", label: "FAQ" },
] as const;

export function Nav() {
	return (
		<header className={styles.header}>
			<div className={`container ${styles.inner}`}>
				<a
					href="#main"
					className={styles.brand}
					aria-label="TapTalk, back to top"
				>
					<img
						src="/icon-64.png"
						width={28}
						height={28}
						alt=""
						className={styles.icon}
					/>
					<span>TapTalk</span>
				</a>
				<nav className={styles.links} aria-label="Sections">
					{links.map((link) => (
						<a key={link.href} href={link.href}>
							{link.label}
						</a>
					))}
				</nav>
				<div className={styles.actions}>
					<ButtonLink
						href={site.repoUrl}
						variant="secondary"
						external
						className={styles.github}
					>
						<Logo name="github" size={16} />
						<StarCount repoSlug={site.repoSlug} fallback="Star" />
					</ButtonLink>
					<ButtonLink href={site.downloadUrl} external>
						Download free
					</ButtonLink>
				</div>
			</div>
		</header>
	);
}
