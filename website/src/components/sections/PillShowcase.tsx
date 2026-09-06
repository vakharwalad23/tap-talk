import { useEffect, useState } from "react";
import { Pill, type PillState } from "#/components/interactive/Pill";
import { useMicLevel } from "#/components/interactive/useMicLevel";
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

export function PillShowcase() {
	const [index, setIndex] = useState(0);
	const [auto, setAuto] = useState(true);
	const mic = useMicLevel();
	const current = cycle[index] ?? cycle[0];
	const state: PillState = mic.active
		? "recording"
		: (current?.state ?? "idle");

	useEffect(() => {
		if (!auto || mic.active) return;
		const timer = window.setTimeout(
			() => setIndex((i) => (i + 1) % cycle.length),
			current?.ms ?? 1000,
		);
		return () => window.clearTimeout(timer);
	}, [auto, current, mic.active]);

	const pick = (target: PillState) => {
		setAuto(false);
		if (mic.active) mic.stop();
		setIndex(
			Math.max(
				0,
				cycle.findIndex((entry) => entry.state === target),
			),
		);
	};

	const toggleMic = () => {
		if (mic.active) {
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
						<Pill
							state={state}
							levelRef={mic.active ? mic.levelRef : undefined}
						/>
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
							pressed={auto && !mic.active}
							variant="ghost"
						>
							Auto play
						</Button>
					</fieldset>
					<div className={styles.mic}>
						<Button onClick={toggleMic} pressed={mic.active}>
							{mic.active ? "Stop my mic" : "Try with my mic"}
						</Button>
						<span className="faint">
							{mic.error ??
								"Your audio stays in this tab. Nothing is sent or recorded."}
						</span>
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
