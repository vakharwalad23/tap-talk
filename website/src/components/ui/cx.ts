import type { CSSProperties } from "react";

export function cx(
	...classes: ReadonlyArray<string | false | null | undefined>
): string {
	return classes.filter(Boolean).join(" ");
}

// Typed custom properties, so components can pass --vars without casting.
export type CSSVars = CSSProperties & Record<`--${string}`, string | number>;
