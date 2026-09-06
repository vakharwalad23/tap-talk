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

export function AppWindow({ active, children, pill }: AppWindowProps) {
	return (
		<div className={styles.stage}>
			<figure
				className={cx(app.window, styles.window)}
				aria-label={`TapTalk app window, ${active} page`}
			>
				<div className={styles.titlebar} aria-hidden="true">
					<span className={cx(styles.light, styles.close)} />
					<span className={cx(styles.light, styles.min)} />
					<span className={cx(styles.light, styles.max)} />
				</div>
				<div className={styles.body}>
					<nav className={styles.sidebar} aria-label="App sections">
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
					<div className={styles.divider} />
					<div className={styles.content}>{children}</div>
				</div>
			</figure>
			{pill ? (
				<div className={styles.pill}>
					<Pill state={pill} />
				</div>
			) : null}
		</div>
	);
}
