import { type LogoName, logoPaths } from "#/content/logo-paths";

interface LogoProps {
	readonly name: LogoName;
	readonly size?: number;
	readonly className?: string;
	readonly label?: string;
}

// simple-icons paths are drawn on a 24x24 grid and filled with currentColor.
export function Logo({ name, size = 20, className, label }: LogoProps) {
	const { title, d } = logoPaths[name];
	const text = label ?? title;
	return (
		<svg
			width={size}
			height={size}
			viewBox="0 0 24 24"
			fill="currentColor"
			role="img"
			aria-label={text}
			className={className}
			focusable={false}
		>
			<title>{text}</title>
			<path d={d} />
		</svg>
	);
}
