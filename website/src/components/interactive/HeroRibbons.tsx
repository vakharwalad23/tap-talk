import { useEffect, useRef, useState } from "react";
import { cx } from "#/components/ui/cx";
import { hero } from "#/content/site";
import styles from "./HeroRibbons.module.css";
import { Pill, type PillState } from "./Pill";

// Two S-curves cross at the pill. Each half is exactly 676 user units long. Each ribbon carries
// its sentence twice on a text pinned to twice that length, so sliding it by one path length
// loops seamlessly.
const PATH_LENGTH = 676;
const paths = {
	speakLow: "M-60 330C260 330 420 280 600 210",
	speakHigh: "M-60 90C260 90 420 140 600 210",
	plainOut: "M600 210C780 140 940 90 1260 90",
	smartOut: "M600 210C780 280 940 330 1260 330",
} as const;

const LOOP = "16s";
const SEPARATOR = "     ";

// Repeat the sentence until one more copy would overflow the path, with a trailing gap so the
// next loop does not run straight into this one.
function fitToPath(text: string, pxPerChar: number): string {
	let out = text;
	while (
		(out.length + SEPARATOR.length + text.length) * pxPerChar <=
		PATH_LENGTH * 0.95
	) {
		out = `${out}${SEPARATOR}${text}`;
	}
	return `${out}${SEPARATOR}`;
}

// lengthAdjust only stretches or squeezes spacing. Sizing the font so the natural text sits
// just under the pinned length keeps letters looking normal whatever font the platform has.
function fitTextToPaths(svg: SVGSVGElement | null): void {
	if (svg === null) return;
	const entries = Array.from(svg.querySelectorAll<SVGTextElement>("text"))
		.map((text) => ({
			text,
			textPath: text.querySelector<SVGTextPathElement>("textPath"),
		}))
		.filter(
			(
				entry,
			): entry is { text: SVGTextElement; textPath: SVGTextPathElement } => {
				return entry.textPath !== null;
			},
		);
	// Unpin every path first and measure in one pass, so layout is forced once, not per ribbon.
	const pinned = entries.map(({ textPath }) =>
		Number(textPath.getAttribute("textLength")),
	);
	for (const { textPath } of entries) textPath.removeAttribute("textLength");
	const natural = entries.map(({ textPath }) =>
		textPath.getComputedTextLength(),
	);
	const base = entries.map(({ text }) =>
		Number.parseFloat(getComputedStyle(text).fontSize),
	);
	entries.forEach(({ text, textPath }, index) => {
		const length = pinned[index] ?? 0;
		const width = natural[index] ?? 0;
		const size = base[index] ?? Number.NaN;
		textPath.setAttribute("textLength", String(length));
		if (width <= 0 || Number.isNaN(size) || length <= 0) return;
		text.style.fontSize = `${(size * length * 0.97) / width}px`;
	});
}

interface RibbonProps {
	readonly id: keyof typeof paths;
	readonly text: string;
	readonly band?: boolean;
	readonly live: boolean;
}

function Ribbon({ id, text, band = false, live }: RibbonProps) {
	const once = fitToPath(text, band ? 9.2 : 8.5);
	return (
		<g>
			<path
				id={`ribbon-${id}`}
				d={paths[id]}
				className={cx(styles.path, band && styles.band)}
			/>
			<text
				className={cx(styles.text, band ? styles.out : styles.in)}
				dominantBaseline="middle"
				xmlSpace="preserve"
			>
				<textPath
					href={`#ribbon-${id}`}
					startOffset="-100%"
					textLength={PATH_LENGTH * 2}
					lengthAdjust="spacing"
				>
					{once}
					{once}
					{live ? (
						<animate
							attributeName="startOffset"
							from="-100%"
							to="0%"
							dur={LOOP}
							repeatCount="indefinite"
						/>
					) : null}
				</textPath>
			</text>
		</g>
	);
}

// Plain dictation first, then the same sentence through Smart Mode.
const script: ReadonlyArray<{ state: PillState; ms: number }> = [
	{ state: "recording", ms: 2600 },
	{ state: "transcribing", ms: 1000 },
	{ state: "done", ms: 1500 },
	{ state: "idle", ms: 700 },
	{ state: "recording", ms: 2600 },
	{ state: "transcribing", ms: 1000 },
	{ state: "rewriting", ms: 1400 },
	{ state: "done", ms: 1500 },
	{ state: "idle", ms: 700 },
];

export function HeroRibbons() {
	const [step, setStep] = useState(0);
	// The prerendered HTML is static text on paths; animation starts once the page is idle so
	// the per-frame text layout never competes with first paint or hydration.
	const [live, setLive] = useState(false);
	const svgRef = useRef<SVGSVGElement>(null);
	const current = script[step] ?? script[0];

	useEffect(() => {
		const start = () => {
			fitTextToPaths(svgRef.current);
			if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches)
				setLive(true);
		};
		// Older Safari has no requestIdleCallback; a short timer is the fallback.
		if (typeof window.requestIdleCallback === "function") {
			const id = window.requestIdleCallback(start, { timeout: 2500 });
			return () => window.cancelIdleCallback(id);
		}
		const timer = window.setTimeout(start, 900);
		return () => window.clearTimeout(timer);
	}, []);

	useEffect(() => {
		if (!live) return;
		const timer = window.setTimeout(
			() => setStep((value) => (value + 1) % script.length),
			current?.ms ?? 1000,
		);
		return () => window.clearTimeout(timer);
	}, [live, current]);

	return (
		<div className={styles.stage}>
			<p className="sr-only">
				Your speech flows into the pill. The plain key pastes it as you said it;
				the Smart key cleans it up on your Mac first.
			</p>
			<svg
				ref={svgRef}
				className={styles.svg}
				viewBox="0 0 1200 420"
				preserveAspectRatio="xMidYMid slice"
				aria-hidden="true"
				focusable={false}
			>
				<Ribbon id="speakLow" text={hero.demo.raw} live={live} />
				<Ribbon id="speakHigh" text={hero.demo.raw} live={live} />
				<Ribbon id="plainOut" text={hero.demo.plain} band live={live} />
				<Ribbon id="smartOut" text={hero.demo.clean} band live={live} />
				<text x="40" y="214" className={styles.label}>
					{hero.demo.speakLabel}
				</text>
				{/* Captions sit between the two output ribbons: the slice crop on wide screens eats the
				    outer rows, so anything near y=50 or y=380 gets cut by the stage edge. */}
				<text x="1160" y="148" textAnchor="end" className={styles.label}>
					{hero.demo.plainLabel}
				</text>
				<text x="1160" y="272" textAnchor="end" className={styles.label}>
					{hero.demo.smartLabel}
				</text>
			</svg>
			<div className={styles.pill}>
				<Pill state={current?.state ?? "recording"} />
			</div>
		</div>
	);
}
