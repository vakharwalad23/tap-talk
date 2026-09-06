import { useEffect, useState } from "react";
import { Pill, type PillState } from "#/components/interactive/Pill";
import {
	type MicStatus,
	useMicLevel,
} from "#/components/interactive/useMicLevel";
import { Button } from "#/components/ui/Button";
import { SectionHeading } from "#/components/ui/SectionHeading";
import styles from "./PillShowcase.module.css";

const cycle: ReadonlyArray<{ state: PillState; ms: number }> = [
	{ state: "recording", ms: 2600 },
	{ state: "transcribing", ms: 1200 },
	{ state: "rewriting", ms: 1400 },
	{ state: "done", ms: 1500 },
	{ state: "idle", ms: 900 },
];

const legend: ReadonlyArray<{ state: PillState; label: string; hint: string }> =
	[
		{
			state: "recording",
			label: "Recording",
			hint: "red, reacts to your voice",
		},
		{
			state: "transcribing",
			label: "Transcribing",
			hint: "white, on the Neural Engine",
		},
		{ state: "rewriting", label: "Rewriting", hint: "purple, Smart Mode only" },
		{ state: "done", label: "Pasted", hint: "green, then it rests" },
		{ state: "idle", label: "Idle", hint: "a thin resting line" },
	];

const micLabel: Record<MicStatus, string> = {
	off: "Try with my mic",
	asking: "Waiting for permission",
	listening: "Stop my mic",
	hearing: "Stop my mic",
};

const micHint: Record<MicStatus, string> = {
	off: "Your audio stays in this tab. Nothing is sent or recorded.",
	asking: "Allow the microphone when your browser asks.",
	listening: "Listening. Say something and watch the helix move.",
	hearing:
		"That is your voice moving the helix. Still nothing leaves this tab.",
};

export function PillShowcase() {
	const [index, setIndex] = useState(0);
	const [auto, setAuto] = useState(true);
	const mic = useMicLevel();
	const live = mic.status === "listening" || mic.status === "hearing";
	const current = cycle[index] ?? cycle[0];
	const state: PillState = live ? "recording" : (current?.state ?? "idle");

	useEffect(() => {
		if (!auto || live) return;
		const timer = window.setTimeout(
			() => setIndex((i) => (i + 1) % cycle.length),
			current?.ms ?? 1000,
		);
		return () => window.clearTimeout(timer);
	}, [auto, current, live]);

	const pick = (target: PillState) => {
		setAuto(false);
		if (mic.status !== "off") mic.stop();
		setIndex(
			Math.max(
				0,
				cycle.findIndex((entry) => entry.state === target),
			),
		);
	};

	const toggleMic = () => {
		if (mic.status !== "off") {
			mic.stop();
			return;
		}
		setAuto(false);
		void mic.start();
	};

	return (
		<section className="section" id="pill" aria-labelledby="pill-title">
			<div className="container">
				<SectionHeading
					eyebrow="The pill"
					title="The pill tells you everything, and nothing leaves your Mac."
					lede="A small floating pill is the whole interface while you dictate. It changes color and shape for each state. Here it is, running live, on this page."
					id="pill-title"
				/>
				<div className={styles.stage} data-reveal>
					<div className={styles.desk} aria-hidden="true" />
					<div className={styles.pill}>
						<Pill state={state} levelRef={live ? mic.levelRef : undefined} />
					</div>
				</div>
				<div className={styles.controls} data-reveal>
					<fieldset className={styles.buttons}>
						<legend className="sr-only">Pill state</legend>
						{legend.map((entry) => (
							<Button
								key={entry.state}
								onClick={() => pick(entry.state)}
								pressed={state === entry.state}
							>
								{entry.label}
							</Button>
						))}
						<Button
							onClick={() => setAuto(true)}
							pressed={auto && !live}
							variant="ghost"
						>
							Auto play
						</Button>
					</fieldset>
					<div className={styles.mic}>
						<Button onClick={toggleMic} pressed={live}>
							{micLabel[mic.status]}
						</Button>
						<output className="faint">
							{mic.error ?? micHint[mic.status]}
						</output>
					</div>
				</div>
				<ul className={styles.legend} data-reveal>
					{legend.map((entry) => (
						<li key={entry.state}>
							<strong>{entry.label}</strong>{" "}
							<span className="muted">{entry.hint}</span>
						</li>
					))}
				</ul>
			</div>
		</section>
	);
}
