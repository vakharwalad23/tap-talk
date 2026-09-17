interface OrukeetMarkProps {
	readonly size?: number;
	readonly className?: string;
	readonly label?: string;
}

// The Oruk "signal" brand mark: a spectrum-gradient tile cut by the signal wave.
// Sourced from oruk.ai. Not a single-path simple-icons glyph, so it is inlined here
// rather than in logo-paths.ts. IDs are namespaced; the mark renders once on the page.
export function OrukeetMark({
	size = 20,
	className,
	label = "Orukeet",
}: OrukeetMarkProps) {
	return (
		<svg
			width={size}
			height={size}
			viewBox="0 0 48 48"
			role="img"
			aria-label={label}
			className={className}
			focusable={false}
		>
			<title>{label}</title>
			<defs>
				<linearGradient
					id="orukeet-spectrum"
					x1="4"
					y1="12"
					x2="44"
					y2="36"
					gradientUnits="userSpaceOnUse"
				>
					<stop offset="0%" stopColor="#306a78" />
					<stop offset="25%" stopColor="#249cd1" />
					<stop offset="44%" stopColor="#454378" />
					<stop offset="62%" stopColor="#7a4382" />
					<stop offset="81%" stopColor="#b85a68" />
					<stop offset="100%" stopColor="#ef8544" />
				</linearGradient>
				<mask
					id="orukeet-cut"
					maskUnits="userSpaceOnUse"
					x="0"
					y="0"
					width="48"
					height="48"
				>
					<rect width="48" height="48" fill="white" />
					<path
						d="M0 27 C10 27 12 14 19 14 S29 34 36 34 S43 23 48 23"
						fill="none"
						stroke="black"
						strokeWidth="3.25"
					/>
				</mask>
			</defs>
			<rect
				x="5"
				y="5"
				width="38"
				height="38"
				rx="1.5"
				fill="url(#orukeet-spectrum)"
				mask="url(#orukeet-cut)"
			/>
		</svg>
	);
}
