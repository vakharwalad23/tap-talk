import { useEffect, useRef, useState } from "react";
import { cx } from "#/components/ui/cx";
import { hero } from "#/content/site";
import styles from "./HeroRibbons.module.css";
import { Pill, type PillState } from "./Pill";

// Two S-curves cross at the pill. Each half is exactly 676 user units long, so text on the
// path can loop seamlessly when its textLength is pinned to that value.
const PATH_LENGTH = 676;
const paths = {
	speakLow: "M-60 330C260 330 420 280 600 210",
	speakHigh: "M-60 90C260 90 420 140 600 210",
	plainOut: "M600 210C780 140 940 90 1260 90",
	smartOut: "M600 210C780 280 940 330 1260 330",
} as const;

const LOOP = "16s";

// Repeat the sentence until one more copy would overflow the path, so lengthAdjust only has
// to stretch spacing a little instead of crushing glyphs together.
function fitToPath(text: string, pxPerChar: number): string {
	const separator = "     ";
	let out = text;
	while (
		(out.length + separator.length + text.length) * pxPerChar <=
		PATH_LENGTH * 0.95
	) {
		out = `${out}${separator}${text}`;
	}
	// Trailing gap, so the looping copy does not run straight into this one.
	return `${out}${separator}`;
}

// lengthAdjust only stretches or squeezes spacing. Sizing the font so the natural text sits
// just under the path length keeps letters looking normal whatever font the platform has.
function fitTextToPaths(svg: SVGSVGElement | null): void {
	if (svg === null) return;
	for (const text of svg.querySelectorAll<SVGTextElement>("text")) {
		const textPath = text.querySelector<SVGTextPathElement>("textPath");
		if (textPath === null) continue;
		textPath.removeAttribute("textLength");
		const natural = textPath.getComputedTextLength();
		textPath.setAttribute("textLength", String(PATH_LENGTH));
		const base = Number.parseFloat(getComputedStyle(text).fontSize);
		if (natural <= 0 || Number.isNaN(base)) continue;
		text.style.fontSize = `${(base * PATH_LENGTH * 0.97) / natural}px`;
	}
}

interface RibbonProps {
	readonly id: keyof typeof paths;
	readonly text: string;
	readonly band?: boolean;
}

function Ribbon({ id, text, band = false }: RibbonProps) {
	const content = fitToPath(text, band ? 9.2 : 8.5);
	const copies = [
		{ key: "a", from: "-100%", to: "0%" },
		{ key: "b", from: "0%", to: "100%" },
	];
	return (
		<g>
			<path
				id={`ribbon-${id}`}
				d={paths[id]}
				className={cx(styles.path, band && styles.band)}
			/>
			{copies.map((copy) => (
				<text
					key={copy.key}
					className={cx(styles.text, band ? styles.out : styles.in)}
					dominantBaseline="middle"
					xmlSpace="preserve"
				>
					<textPath
						href={`#ribbon-${id}`}
						startOffset={copy.from}
						textLength={PATH_LENGTH}
						lengthAdjust="spacing"
					>
						{content}
						<animate
							attributeName="startOffset"
							from={copy.from}
							to={copy.to}
							dur={LOOP}
							repeatCount="indefinite"
						/>
					</textPath>
				</text>
			))}
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
	const svgRef = useRef<SVGSVGElement>(null);
	const current = script[step] ?? script[0];

	useEffect(() => {
		fitTextToPaths(svgRef.current);
	}, []);

	useEffect(() => {
		if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
			svgRef.current?.pauseAnimations();
			return;
		}
		const timer = window.setTimeout(
			() => setStep((value) => (value + 1) % script.length),
			current?.ms ?? 1000,
		);
		return () => window.clearTimeout(timer);
	}, [current]);

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
				<Ribbon id="speakLow" text={hero.demo.raw} />
				<Ribbon id="speakHigh" text={hero.demo.raw} />
				<Ribbon id="plainOut" text={hero.demo.plain} band />
				<Ribbon id="smartOut" text={hero.demo.clean} band />
				<text x="40" y="214" className={styles.label}>
					{hero.demo.speakLabel}
				</text>
				<text x="1160" y="52" textAnchor="end" className={styles.label}>
					{hero.demo.plainLabel}
				</text>
				<text x="1160" y="380" textAnchor="end" className={styles.label}>
					{hero.demo.smartLabel}
				</text>
			</svg>
			<div className={styles.pill}>
				<Pill state={current?.state ?? "recording"} />
			</div>
		</div>
	);
}
