import { useEffect, useRef, useState } from "react";
import { StarCount } from "#/components/interactive/StarCount";
import { useScrollSpy } from "#/components/interactive/useScrollSpy";
import { ButtonLink } from "#/components/ui/Button";
import { type CSSVars, cx } from "#/components/ui/cx";
import { Logo } from "#/components/ui/Logo";
import { site } from "#/content/site";
import styles from "./Nav.module.css";

const links = [
	{ id: "how", label: "How it works" },
	{ id: "features", label: "Features" },
	{ id: "intelligence", label: "Intelligence" },
	{ id: "compare", label: "Compare" },
	{ id: "setup", label: "Setup" },
	{ id: "faq", label: "FAQ" },
] as const;

// Every section on the page, in order, and the nav entry it lights up.
const sectionToLink: Readonly<Record<string, (typeof links)[number]["id"]>> = {
	how: "how",
	pill: "how",
	features: "features",
	speed: "features",
	intelligence: "intelligence",
	languages: "intelligence",
	apps: "intelligence",
	inside: "compare",
	compare: "compare",
	privacy: "compare",
	"open-source": "setup",
	setup: "setup",
	tech: "setup",
	faq: "faq",
};
const sectionIds = Object.keys(sectionToLink);

export function Nav() {
	const activeSection = useScrollSpy(sectionIds);
	const activeLink = activeSection ? sectionToLink[activeSection] : undefined;
	const listRef = useRef<HTMLElement>(null);
	const [indicator, setIndicator] = useState<{ x: number; w: number } | null>(
		null,
	);

	useEffect(() => {
		const measure = () => {
			const list = listRef.current;
			if (list === null || activeLink === undefined) {
				setIndicator(null);
				return;
			}
			const anchor = list.querySelector<HTMLAnchorElement>(
				`a[href="#${activeLink}"]`,
			);
			if (anchor === null) return;
			setIndicator({ x: anchor.offsetLeft, w: anchor.offsetWidth });
		};
		measure();
		window.addEventListener("resize", measure);
		return () => window.removeEventListener("resize", measure);
	}, [activeLink]);

	const indicatorVars: CSSVars = {
		"--x": `${indicator?.x ?? 0}px`,
		"--w": `${indicator?.w ?? 0}px`,
	};

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
				<nav className={styles.links} aria-label="Sections" ref={listRef}>
					{links.map((link) => (
						<a
							key={link.id}
							href={`#${link.id}`}
							className={cx(link.id === activeLink && styles.active)}
							aria-current={link.id === activeLink ? "true" : undefined}
						>
							{link.label}
						</a>
					))}
					<span
						className={cx(
							styles.indicator,
							indicator !== null && styles.indicatorOn,
						)}
						style={indicatorVars}
						aria-hidden="true"
					/>
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
