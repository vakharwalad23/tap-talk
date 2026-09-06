import { useEffect, useState } from "react";
import { cx } from "#/components/ui/cx";
import styles from "./TypedDemo.module.css";

interface TypedDemoProps {
	readonly raw: string;
	readonly clean: string;
	readonly caption: string;
}

type Phase = "typing" | "hold" | "clean";

const TYPE_MS = 38;
const HOLD_MS = 900;
const CLEAN_MS = 3200;

// Server-rendered output is the finished result; the animation only starts after hydration,
// so the prerendered HTML and the first client render match.
export function TypedDemo({ raw, clean, caption }: TypedDemoProps) {
	const [phase, setPhase] = useState<Phase>("clean");
	const [typed, setTyped] = useState(raw.length);

	useEffect(() => {
		if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
		let timer = 0;
		let cancelled = false;

		const run = (count: number) => {
			if (cancelled) return;
			if (count <= raw.length) {
				setPhase("typing");
				setTyped(count);
				timer = window.setTimeout(() => run(count + 1), TYPE_MS);
				return;
			}
			setPhase("hold");
			timer = window.setTimeout(() => {
				if (cancelled) return;
				setPhase("clean");
				timer = window.setTimeout(() => run(0), CLEAN_MS);
			}, HOLD_MS);
		};

		timer = window.setTimeout(() => run(0), 600);
		return () => {
			cancelled = true;
			window.clearTimeout(timer);
		};
	}, [raw.length]);

	const showClean = phase === "clean";
	return (
		<div className={styles.field} aria-live="off">
			<div className={styles.chrome}>
				<span className={styles.dot} />
				<span className={styles.dot} />
				<span className={styles.dot} />
				<span className={styles.title}>Notes</span>
			</div>
			<p className={cx(styles.text, showClean && styles.clean)}>
				{showClean ? clean : raw.slice(0, typed)}
				<span
					className={cx(styles.caret, phase === "typing" && styles.caretOn)}
				/>
			</p>
			<p className={styles.caption}>
				<span className={cx(styles.tag, showClean && styles.tagOn)}>
					Smart Mode
				</span>
				{caption}
			</p>
		</div>
	);
}
