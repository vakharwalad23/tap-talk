import type { SVGProps } from "react";

const strokeIcons = {
	check: "M5 12.5l4.5 4.5L19 7",
	x: "M6 6l12 12M18 6L6 18",
	minus: "M6 12h12",
	arrowRight: "M5 12h14M13 6l6 6-6 6",
	arrowUpRight: "M7 17L17 7M8 7h9v9",
	copy: "M9 9h10v10H9zM5 15V5h10",
	keyboard: "M3 7h18v10H3zM7 11h1M11 11h1M15 11h1M8 14h8",
	mic: "M12 3a3 3 0 0 1 3 3v6a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3zM5 11a7 7 0 0 0 14 0M12 18v3",
	globe:
		"M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM3 12h18M12 3c3 3.5 3 14.5 0 18M12 3c-3 3.5-3 14.5 0 18",
	cloud: "M7 18a4 4 0 0 1-.5-8A6 6 0 0 1 18 9a4 4 0 0 1 0 9z",
	chip: "M7 7h10v10H7zM10 4v3M14 4v3M10 17v3M14 17v3M4 10h3M4 14h3M17 10h3M17 14h3",
	lock: "M6 11h12v9H6zM9 11V7a3 3 0 0 1 6 0v4",
	mail: "M3 6h18v12H3zM3 7l9 6 9-6",
	terminal: "M4 5h16v14H4zM7 9l3 3-3 3M12 15h5",
	messages: "M4 5h16v11H9l-5 4z",
	code: "M8 7l-5 5 5 5M16 7l5 5-5 5M14 4l-4 16",
	notes: "M6 3h12v18H6zM9 8h6M9 12h6M9 16h4",
	fork: "M7 4a2 2 0 1 0 0 4 2 2 0 0 0 0-4zM17 4a2 2 0 1 0 0 4 2 2 0 0 0 0-4zM12 16a2 2 0 1 0 0 4 2 2 0 0 0 0-4zM7 8v1a4 4 0 0 0 4 4h2a4 4 0 0 0 4-4V8M12 13v3",
	issue: "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM12 8v5M12 16v.5",
	download: "M12 4v11M7 10l5 5 5-5M5 20h14",
	menuBar: "M3 5h18M3 5v3h18V5",
	stop: "M7 7h10v10H7z",
} as const;

const fillIcons = {
	star: "M12 2.5l2.9 6.1 6.6.8-4.9 4.6 1.3 6.6L12 17.3l-5.9 3.3 1.3-6.6L2.5 9.4l6.6-.8z",
	bolt: "M13 2L4 14h6l-1 8 9-12h-6z",
} as const;

export type IconName = keyof typeof strokeIcons | keyof typeof fillIcons;

interface IconProps {
	readonly name: IconName;
	readonly size?: number;
	readonly className?: string;
	readonly title?: string;
}

function isFill(name: IconName): name is keyof typeof fillIcons {
	return name in fillIcons;
}

const strokePaint: SVGProps<SVGSVGElement> = {
	fill: "none",
	stroke: "currentColor",
	strokeWidth: 2,
	strokeLinecap: "round",
	strokeLinejoin: "round",
};

const fillPaint: SVGProps<SVGSVGElement> = { fill: "currentColor" };

// Decorative by default (aria-hidden); pass a title to expose the icon to assistive tech.
export function Icon({ name, size = 18, className, title }: IconProps) {
	const d = isFill(name) ? fillIcons[name] : strokeIcons[name];
	const paint = isFill(name) ? fillPaint : strokePaint;

	if (title !== undefined) {
		return (
			<svg
				width={size}
				height={size}
				viewBox="0 0 24 24"
				className={className}
				role="img"
				aria-label={title}
				focusable={false}
				{...paint}
			>
				<title>{title}</title>
				<path d={d} />
			</svg>
		);
	}
	return (
		<svg
			width={size}
			height={size}
			viewBox="0 0 24 24"
			className={className}
			aria-hidden="true"
			focusable={false}
			{...paint}
		>
			<path d={d} />
		</svg>
	);
}
