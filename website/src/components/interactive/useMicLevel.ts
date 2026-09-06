import { useCallback, useEffect, useRef, useState } from "react";

interface MicLevel {
	readonly active: boolean;
	readonly error: string | null;
	readonly levelRef: React.RefObject<number>;
	readonly start: () => Promise<void>;
	readonly stop: () => void;
}

// Feeds a raw RMS level (about 0 to 0.3, like the app's cpal callback) into a ref at frame rate.
export function useMicLevel(): MicLevel {
	const levelRef = useRef(0);
	const [active, setActive] = useState(false);
	const [error, setError] = useState<string | null>(null);
	const streamRef = useRef<MediaStream | null>(null);
	const contextRef = useRef<AudioContext | null>(null);
	const frameRef = useRef(0);

	const stop = useCallback(() => {
		cancelAnimationFrame(frameRef.current);
		for (const track of streamRef.current?.getTracks() ?? []) track.stop();
		streamRef.current = null;
		void contextRef.current?.close();
		contextRef.current = null;
		levelRef.current = 0;
		setActive(false);
	}, []);

	const start = useCallback(async () => {
		setError(null);
		try {
			const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
			const context = new AudioContext();
			const analyser = context.createAnalyser();
			analyser.fftSize = 1024;
			context.createMediaStreamSource(stream).connect(analyser);
			const samples = new Float32Array(analyser.fftSize);

			const tick = () => {
				analyser.getFloatTimeDomainData(samples);
				let sum = 0;
				for (const sample of samples) sum += sample * sample;
				levelRef.current = Math.sqrt(sum / samples.length);
				frameRef.current = requestAnimationFrame(tick);
			};

			streamRef.current = stream;
			contextRef.current = context;
			frameRef.current = requestAnimationFrame(tick);
			setActive(true);
		} catch {
			setError("Microphone access was not granted.");
			setActive(false);
		}
	}, []);

	useEffect(() => stop, [stop]);

	return { active, error, levelRef, start, stop };
}
