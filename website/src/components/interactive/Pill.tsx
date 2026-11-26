import { type RefObject, useEffect, useRef } from "react";
import { cx } from "#/components/ui/cx";
import { Icon } from "#/components/ui/Icon";
import styles from "./Pill.module.css";
import { LEVEL_GAIN, syntheticLevel } from "./pillLevel";

export type PillState =
	| "idle"
	| "recording"
	| "transcribing"
	| "rewriting"
	| "done";

interface PillProps {
	readonly state: PillState;
	// Live mic level in raw RMS units. Read on every frame, so it is a ref, not a prop value.
	readonly levelRef?: RefObject<number>;
	readonly className?: string;
}

// Web pixels per app point, as in Pill.module.css.
const POINT = 1.6;
// PillRecordingRow.swift: center bars swing further than the edges, so speech reads as a waveform.
const BAR_PROFILE = Array.from(
	{ length: 11 },
	(_, i) => 0.45 + 0.55 * Math.sin((i / 10) * Math.PI),
);
const BAR_KEYS = BAR_PROFILE.map((_, i) => `bar-${i}`);

function clock(seconds: number): string {
	const s = Math.max(0, Math.floor(seconds));
	return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

interface RecordingRowProps {
	readonly levelRef?: RefObject<number>;
}

// Bars and timer are written straight to the DOM each frame so React never re-renders at 60 fps.
function RecordingRow({ levelRef }: RecordingRowProps) {
	const barsRef = useRef<HTMLSpanElement>(null);
	const clockRef = useRef<HTMLSpanElement>(null);

	useEffect(() => {
		const clockEl = clockRef.current;
		const bars = barsRef.current?.querySelectorAll<HTMLSpanElement>("span");
		if (clockEl === null || bars === undefined) return;
		const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
		const start = performance.now();
		let last = start;
		let level = 0;
		let shown = "";
		let frame = 0;

		const tick = (now: number) => {
			const dt = Math.min(3, (now - last) / (1000 / 60));
			last = now;
			const seconds = (now - start) / 1000;
			const raw = levelRef?.current ?? syntheticLevel(seconds);
			const target = Math.min(1, Math.max(0, raw * LEVEL_GAIN));
			level += (target - level) * 0.25 * dt;
			const phase = still ? 0 : seconds;
			bars.forEach((bar, i) => {
				const sway = 0.7 + 0.3 * Math.sin(phase * 9 + i * 1.3);
				const points = 2.5 + 15 * level * (BAR_PROFILE[i] ?? 1) * sway;
				bar.style.height = `${points * POINT}px`;
			});
			const text = clock(seconds);
			if (text !== shown) {
				clockEl.textContent = text;
				shown = text;
			}
			frame = requestAnimationFrame(tick);
		};
		frame = requestAnimationFrame(tick);
		return () => cancelAnimationFrame(frame);
	}, [levelRef]);

	return (
		<>
			<span className={cx(styles.button, styles.cancel)}>
				<Icon name="x" size={15} strokeWidth={3.4} />
			</span>
			<span ref={clockRef} className={styles.clock}>
				0:00
			</span>
			<span ref={barsRef} className={styles.bars}>
				{BAR_KEYS.map((key) => (
					<span key={key} />
				))}
			</span>
			<span className={cx(styles.button, styles.finish)}>
				<Icon name="check" size={19} strokeWidth={3.4} />
			</span>
		</>
	);
}

function PillContent({ state, levelRef }: PillProps) {
	switch (state) {
		case "recording":
			return <RecordingRow levelRef={levelRef} />;
		case "transcribing":
			return <span className={styles.shimmer} />;
		case "rewriting":
			return (
				<>
					<Icon name="sparkles" size={20} className={styles.smart} />
					Rewriting
				</>
			);
		case "done":
			return (
				<>
					<Icon
						name="check"
						size={20}
						strokeWidth={3.4}
						className={styles.ok}
					/>
					Pasted
				</>
			);
		case "idle":
			return null;
	}
}

// Mirrors PillView.swift: a frosted capsule that follows the light or dark appearance.
export function Pill({ state, levelRef, className }: PillProps) {
	return (
		<div
			className={cx(styles.frame, className)}
			role="img"
			aria-label={`TapTalk pill, ${state}`}
		>
			{state === "idle" ? (
				<div className={cx(styles.glass, styles.idleBar)} />
			) : (
				// Keyed by state so each change replays the pop, like the app's scale and fade transition.
				<div
					key={state}
					className={cx(styles.glass, styles.capsule, styles[state])}
				>
					<PillContent state={state} levelRef={levelRef} />
				</div>
			)}
		</div>
	);
}
