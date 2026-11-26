// Raw mic RMS sits around 0 to 0.3; the app multiplies by 12 to reach a 0 to 1 swing.
export const LEVEL_GAIN = 12;

// A stand-in for a voice: syllable bursts inside a slower phrase envelope, in raw RMS units.
export function syntheticLevel(seconds: number): number {
	const syllables = Math.max(
		0,
		Math.sin(seconds * 7.1) + 0.35 * Math.sin(seconds * 12.7),
	);
	const phrase = 0.55 + 0.45 * Math.sin(seconds * 1.3);
	return 0.03 + 0.22 * syllables * phrase;
}
