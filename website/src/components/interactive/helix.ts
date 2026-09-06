// Geometry mirrors PillView.swift, scaled for the web. Points in the app map to px here.
export const PILL_SCALE = 1.6;

export const pillGeometry = {
	frame: { w: 156 * PILL_SCALE, h: 40 * PILL_SCALE },
	capsuleHeight: 30 * PILL_SCALE,
	widths: {
		recording: 96 * PILL_SCALE,
		transcribing: 96 * PILL_SCALE,
		rewriting: 124 * PILL_SCALE,
		done: 104 * PILL_SCALE,
	},
	helix: { w: 76 * PILL_SCALE, h: 22 * PILL_SCALE },
	helixSmall: { w: 44 * PILL_SCALE, h: 20 * PILL_SCALE },
	idleBar: { w: 54 * PILL_SCALE, h: 4 * PILL_SCALE },
} as const;

export const pillColors = {
	recording: "#ff4d42",
	transcribing: "rgba(255, 255, 255, 0.85)",
	rewriting: "#9e7aff",
} as const;

// Raw mic RMS sits around 0 to 0.3; the app multiplies by 12 to reach a 0 to 1 swing.
export const LEVEL_GAIN = 12;

const DOT_COUNT = 14;
const WAVES = 1.6;
const DOT_RADIUS = 1.7 * PILL_SCALE;

export function drawHelix(
	ctx: CanvasRenderingContext2D,
	width: number,
	height: number,
	phase: number,
	amplitude: number,
	color: string,
): void {
	ctx.clearRect(0, 0, width, height);
	const cy = height / 2;
	const maxAmp = Math.max(0, height / 2 - 2 * PILL_SCALE);
	const amp = maxAmp * Math.min(1, Math.max(0, amplitude));

	for (let i = 0; i < DOT_COUNT; i += 1) {
		const t = i / (DOT_COUNT - 1);
		const x = width * t;
		const angle = t * WAVES * 2 * Math.PI + phase;
		const yA = cy + amp * Math.sin(angle);
		const yB = cy + amp * Math.sin(angle + Math.PI);

		ctx.globalAlpha = 1;
		ctx.fillStyle = color;
		ctx.beginPath();
		ctx.arc(x, yA, DOT_RADIUS, 0, Math.PI * 2);
		ctx.fill();

		ctx.globalAlpha = 0.5;
		ctx.beginPath();
		ctx.arc(x, yB, DOT_RADIUS, 0, Math.PI * 2);
		ctx.fill();
	}
	ctx.globalAlpha = 1;
}

// A stand-in for a voice: syllable bursts inside a slower phrase envelope, in raw RMS units.
export function syntheticLevel(seconds: number): number {
	const syllables = Math.max(
		0,
		Math.sin(seconds * 7.1) + 0.35 * Math.sin(seconds * 12.7),
	);
	const phrase = 0.55 + 0.45 * Math.sin(seconds * 1.3);
	return 0.03 + 0.22 * syllables * phrase;
}
