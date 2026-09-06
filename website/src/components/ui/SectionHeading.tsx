import type { ReactNode } from "react";
import { cx } from "./cx";
import styles from "./SectionHeading.module.css";

interface SectionHeadingProps {
	readonly eyebrow?: string;
	readonly title: string;
	readonly lede?: ReactNode;
	readonly align?: "left" | "center";
	readonly id?: string;
}

export function SectionHeading({
	eyebrow,
	title,
	lede,
	align = "left",
	id,
}: SectionHeadingProps) {
	return (
		<div
			className={cx(styles.wrap, align === "center" && styles.center)}
			data-reveal
		>
			{eyebrow ? <span className="eyebrow">{eyebrow}</span> : null}
			<h2 id={id}>{title}</h2>
			{lede ? <p className="lede">{lede}</p> : null}
		</div>
	);
}
