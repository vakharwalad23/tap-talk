import { type RefObject, useEffect, useRef } from "react";
import { cx } from "#/components/ui/cx";
import { Icon } from "#/components/ui/Icon";
import {
	drawHelix,
	LEVEL_GAIN,
	pillColors,
	pillGeometry,
	syntheticLevel,
} from "./helix";
import styles from "./Pill.module.css";

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

const PHASE_STEP: Record<PillState, number> = {
	idle: 0,
	done: 0,
	recording: 0.13,
	transcribing: 0.24,
	rewriting: 0.24,
};

function helixSize(state: PillState) {
	return state === "rewriting" ? pillGeometry.helixSmall : pillGeometry.helix;
}

export function Pill({ state, levelRef, className }: PillProps) {
	const canvasRef = useRef<HTMLCanvasElement>(null);
	const animated =
		state === "recording" || state === "transcribing" || state === "rewriting";

	useEffect(() => {
		const canvas = canvasRef.current;
		if (!animated || canvas === null) return;
		const ctx = canvas.getContext("2d");
		if (ctx === null) return;

		const { w, h } = helixSize(state);
		const dpr = window.devicePixelRatio || 1;
		canvas.width = Math.round(w * dpr);
		canvas.height = Math.round(h * dpr);
		ctx.scale(dpr, dpr);

		let phase = 0;
		let displayLevel = 0;
		let last = performance.now();
		let frame = 0;
		const start = last;

		const tick = (now: number) => {
			const dt = Math.min(3, (now - last) / (1000 / 60));
			last = now;
			phase += PHASE_STEP[state] * dt;

			let amplitude = 0.4;
			if (state === "recording") {
				const raw = levelRef?.current ?? syntheticLevel((now - start) / 1000);
				const target = Math.min(1, Math.max(0, raw * LEVEL_GAIN));
				displayLevel += (target - displayLevel) * 0.25 * dt;
				amplitude = 0.6 + 0.4 * displayLevel;
			}
			drawHelix(ctx, w, h, phase, amplitude, pillColors[state]);
			frame = requestAnimationFrame(tick);
		};
		frame = requestAnimationFrame(tick);
		return () => cancelAnimationFrame(frame);
	}, [state, animated, levelRef]);

	if (state === "idle") {
		return (
			<div
				className={cx(styles.frame, className)}
				role="img"
				aria-label="TapTalk pill, idle"
			>
				<div className={styles.idleBar} />
			</div>
		);
	}

	const { w, h } = helixSize(state);
	return (
		<div
			className={cx(styles.frame, className)}
			role="img"
			aria-label={`TapTalk pill, ${state}`}
		>
			<div className={cx(styles.capsule, styles[state])}>
				{animated ? (
					<canvas
						ref={canvasRef}
						className={styles.canvas}
						style={{ width: w, height: h }}
					/>
				) : null}
				{state === "rewriting" ? (
					<span className={styles.label}>Rewriting</span>
				) : null}
				{state === "done" ? (
					<>
						<Icon name="check" size={13 * 1.6} className={styles.check} />
						<span className={styles.doneLabel}>Pasted</span>
					</>
				) : null}
			</div>
		</div>
	);
}
