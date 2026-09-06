import { type CSSVars, cx } from "#/components/ui/cx";
import { Logo } from "#/components/ui/Logo";
import { models, siteBuiltWith } from "#/content/logos";
import { site } from "#/content/site";
import styles from "./Footer.module.css";

const links = [
	{ href: site.repoUrl, label: "GitHub" },
	{ href: site.releasesUrl, label: "Releases" },
	{ href: site.issuesUrl, label: "Report an issue" },
	{ href: site.licenseUrl, label: "MIT License" },
	{ href: "#privacy", label: "Privacy" },
] as const;

// The waveform mark: seven bars, heights as a share of the box.
const bars = [
	{ id: "b1", h: 46 },
	{ id: "b2", h: 72 },
	{ id: "b3", h: 100 },
	{ id: "b4", h: 60 },
	{ id: "b5", h: 86 },
	{ id: "b6", h: 52 },
	{ id: "b7", h: 34 },
] as const;

export function Footer() {
	return (
		<footer className={styles.footer}>
			<div className={`container ${styles.grid}`}>
				<div className={styles.brand}>
					<div className={styles.logoRow}>
						<img
							src="/icon-64.png"
							width={32}
							height={32}
							alt=""
							className={styles.icon}
						/>
						<strong>TapTalk</strong>
					</div>
					<p className="muted">
						Free, open-source, on-device dictation for Mac.
					</p>
				</div>
				<nav className={styles.col} aria-label="Footer">
					<h3>Project</h3>
					<ul>
						{links.map((link) => (
							<li key={link.href}>
								<a
									href={link.href}
									target={link.href.startsWith("#") ? undefined : "_blank"}
									rel={
										link.href.startsWith("#")
											? undefined
											: "noopener noreferrer"
									}
								>
									{link.label}
								</a>
							</li>
						))}
					</ul>
				</nav>
				<div className={styles.col}>
					<h3>Model attributions</h3>
					<ul>
						{models.map((model) => (
							<li key={model.name}>
								<a href={model.url} target="_blank" rel="noopener noreferrer">
									{model.name}
								</a>
								<span className="faint"> {model.license}</span>
							</li>
						))}
					</ul>
				</div>
				<div className={styles.col}>
					<h3>This site</h3>
					<p className="faint">
						Prerendered with TanStack Start, served from Cloudflare.
					</p>
					<ul className={styles.siteLogos}>
						{siteBuiltWith.map((entry) => (
							<li key={entry.name}>
								<a
									href={entry.url}
									target="_blank"
									rel="noopener noreferrer"
									aria-label={entry.name}
								>
									{entry.logo ? (
										<Logo name={entry.logo} size={18} label={entry.name} />
									) : null}
								</a>
							</li>
						))}
					</ul>
				</div>
			</div>

			<div className={`container ${styles.mark}`} data-reveal>
				<svg
					className={styles.wave}
					viewBox="0 0 132 100"
					aria-hidden="true"
					focusable={false}
				>
					{bars.map((bar, index) => {
						const vars: CSSVars = { "--i": index };
						return (
							<rect
								key={bar.id}
								className={styles.bar}
								style={vars}
								x={index * 20}
								y={(100 - bar.h) / 2}
								width={12}
								height={bar.h}
								rx={6}
							/>
						);
					})}
				</svg>
				<span className={cx(styles.wordmark)} aria-hidden="true">
					TapTalk
				</span>
			</div>

			<div className={`container ${styles.bottom}`}>
				<span className="faint">
					Made by{" "}
					<a href={site.authorUrl} target="_blank" rel="noopener noreferrer">
						{site.authorName}
					</a>
					. MIT License.
				</span>
				<span className="faint">
					Version {site.version}, updated {site.lastUpdated}.
				</span>
			</div>
		</footer>
	);
}
