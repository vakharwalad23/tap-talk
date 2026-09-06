import { useCallback, useEffect, useRef, useState } from "react";

export type MicStatus = "off" | "asking" | "listening" | "hearing";

interface MicLevel {
	readonly status: MicStatus;
	readonly error: string | null;
	readonly levelRef: React.RefObject<number>;
	readonly start: () => Promise<void>;
	readonly stop: () => void;
}

// Speech at normal input gain sits well above this; room noise stays under it.
const HEARD_RMS = 0.02;

// Feeds a raw RMS level (about 0 to 0.3, like the app's cpal callback) into a ref at frame rate.
export function useMicLevel(): MicLevel {
	const levelRef = useRef(0);
	const [status, setStatus] = useState<MicStatus>("off");
	const [error, setError] = useState<string | null>(null);
	const streamRef = useRef<MediaStream | null>(null);
	const contextRef = useRef<AudioContext | null>(null);
	const frameRef = useRef(0);
	const generation = useRef(0);

	const stop = useCallback(() => {
		generation.current += 1;
		cancelAnimationFrame(frameRef.current);
		for (const track of streamRef.current?.getTracks() ?? []) track.stop();
		streamRef.current = null;
		void contextRef.current?.close();
		contextRef.current = null;
		levelRef.current = 0;
		setStatus("off");
	}, []);

	const start = useCallback(async () => {
		setError(null);
		setStatus("asking");
		generation.current += 1;
		const ticket = generation.current;
		// Safari only runs an AudioContext created inside the click handler. Created after the
		// permission await it stays suspended and the analyser reads silence forever.
		const context = new AudioContext();
		try {
			const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
			// Stop was pressed while the permission prompt was open.
			if (ticket !== generation.current) {
				for (const track of stream.getTracks()) track.stop();
				void context.close();
				return;
			}
			void context.resume();
			const analyser = context.createAnalyser();
			analyser.fftSize = 1024;
			context.createMediaStreamSource(stream).connect(analyser);
			const samples = new Float32Array(analyser.fftSize);
			let heard = false;

			const tick = () => {
				analyser.getFloatTimeDomainData(samples);
				let sum = 0;
				for (const sample of samples) sum += sample * sample;
				const rms = Math.sqrt(sum / samples.length);
				levelRef.current = rms;
				if (!heard && rms > HEARD_RMS) {
					heard = true;
					setStatus("hearing");
				}
				frameRef.current = requestAnimationFrame(tick);
			};

			streamRef.current = stream;
			contextRef.current = context;
			frameRef.current = requestAnimationFrame(tick);
			setStatus("listening");
		} catch {
			void context.close();
			if (ticket !== generation.current) return;
			setError(
				"Microphone blocked. Allow it in the address bar, or in System Settings > Privacy & Security > Microphone.",
			);
			setStatus("off");
		}
	}, []);

	useEffect(() => stop, [stop]);

	return { status, error, levelRef, start, stop };
}
