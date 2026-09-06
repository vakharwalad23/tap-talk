import type { ReactNode } from "react";
import { Pill, type PillState } from "#/components/interactive/Pill";
import { cx } from "#/components/ui/cx";
import styles from "./AppWindow.module.css";
import app from "./app.module.css";

export const navItems = [
	"Record",
	"Models",
	"Settings",
	"Intelligence",
	"Privacy",
	"About",
] as const;
export type NavItem = (typeof navItems)[number];

interface AppWindowProps {
	readonly active: NavItem;
	readonly children: ReactNode;
	readonly pill?: PillState;
}

// The window is laid out at its real size (580 x 480 points, hidden title bar) and scaled.
export function AppWindow({ active, children, pill }: AppWindowProps) {
	return (
		<div className={styles.stage}>
			<div className={styles.frame}>
				<figure
					className={cx(app.window, styles.window)}
					aria-label={`TapTalk app window, ${active} page`}
				>
					<nav className={styles.sidebar} aria-label="App sections">
						<div className={styles.lights} aria-hidden="true">
							<span className={styles.close} />
							<span className={styles.min} />
							<span className={styles.max} />
						</div>
						<div className={styles.brand}>TapTalk</div>
						<ul className={styles.nav}>
							{navItems.map((item) => (
								<li
									key={item}
									className={cx(
										styles.navItem,
										item === active && styles.navActive,
									)}
								>
									{item}
								</li>
							))}
						</ul>
					</nav>
					<div className={styles.content}>{children}</div>
				</figure>
			</div>
			{pill ? (
				<div className={styles.pill}>
					<Pill state={pill} />
				</div>
			) : null}
		</div>
	);
}
