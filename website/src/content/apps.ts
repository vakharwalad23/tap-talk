import type { LogoName } from "./logo-paths";

export type GlyphName = "mail" | "terminal" | "messages" | "code" | "notes";

export interface AppEntry {
	readonly name: string;
	readonly logo?: LogoName;
	readonly glyph?: GlyphName;
}

export const apps: readonly AppEntry[] = [
	{ name: "Mail", glyph: "mail" },
	{ name: "Slack", logo: "slack" },
	{ name: "Notion", logo: "notion" },
	{ name: "Xcode", logo: "xcode" },
	{ name: "VS Code", glyph: "code" },
	{ name: "Terminal", glyph: "terminal" },
	{ name: "Safari", logo: "safari" },
	{ name: "Chrome", logo: "googlechrome" },
	{ name: "Messages", glyph: "messages" },
	{ name: "Cursor", logo: "cursor" },
	{ name: "Discord", logo: "discord" },
	{ name: "Notes", glyph: "notes" },
];

export const appsCopy = {
	title: "Anywhere you can type, you can talk.",
	body: "TapTalk pastes into the focused field of any macOS app, including the Chromium and Electron apps (VS Code, Slack, Discord) that trip up other dictation tools.",
} as const;
