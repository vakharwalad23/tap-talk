import type { ReactNode } from "react";
import styles from "./Button.module.css";
import { cx } from "./cx";

type Variant = "primary" | "secondary" | "ghost";
type Size = "md" | "lg";

interface ButtonLinkProps {
	readonly href: string;
	readonly children: ReactNode;
	readonly variant?: Variant;
	readonly size?: Size;
	readonly external?: boolean;
	readonly className?: string;
}

export function ButtonLink({
	href,
	children,
	variant = "primary",
	size = "md",
	external = false,
	className,
}: ButtonLinkProps) {
	return (
		<a
			href={href}
			className={cx(styles.button, styles[variant], styles[size], className)}
			target={external ? "_blank" : undefined}
			rel={external ? "noopener noreferrer" : undefined}
		>
			{children}
		</a>
	);
}

interface ButtonProps {
	readonly children: ReactNode;
	readonly onClick?: () => void;
	readonly variant?: Variant;
	readonly size?: Size;
	readonly pressed?: boolean;
	readonly className?: string;
}

export function Button({
	children,
	onClick,
	variant = "secondary",
	size = "md",
	pressed,
	className,
}: ButtonProps) {
	return (
		<button
			type="button"
			onClick={onClick}
			aria-pressed={pressed}
			className={cx(styles.button, styles[variant], styles[size], className)}
		>
			{children}
		</button>
	);
}
