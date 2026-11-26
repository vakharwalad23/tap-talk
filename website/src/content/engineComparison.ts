export type EngineLead = "orukeet" | "parakeet" | "tie" | "none";

export interface EngineRow {
	readonly label: string;
	readonly orukeet: string;
	readonly parakeet: string;
	readonly lead: EngineLead;
	// Short chip shown under the metric label, e.g. the speed row's parity note.
	readonly note?: string;
}

export interface EngineColumn {
	readonly name: string;
	readonly tagline: string;
	readonly url: string;
}

export interface EngineComparison {
	readonly eyebrow: string;
	readonly title: string;
	readonly lede: string;
	readonly orukeet: EngineColumn;
	readonly parakeet: EngineColumn;
	readonly rows: readonly EngineRow[];
	readonly footnote: string;
}

export const engineComparison: EngineComparison = {
	eyebrow: "Two on-device engines",
	title: "Orukeet or Parakeet, side by side.",
	lede: "Both run entirely on the Neural Engine for English and 24 European languages. Orukeet is the recommended default for new installs; Parakeet stays as the fallback and the base for optional live typing.",
	orukeet: {
		name: "Orukeet",
		tagline: "Recommended default",
		url: "https://oruk.ai",
	},
	parakeet: {
		name: "Parakeet",
		tagline: "Fallback and live-typing base",
		url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml",
	},
	rows: [
		{
			label: "Accuracy",
			orukeet: "About 15% fewer word errors (25-language FLEURS)",
			parakeet: "Baseline",
			lead: "orukeet",
		},
		{
			label: "Speed (key-up-to-paste)",
			orukeet: "~104 ms",
			parakeet: "~95 ms",
			lead: "tie",
			note: "Both about 0.1 s",
		},
		{
			label: "Languages",
			orukeet: "English + 24 European (auto)",
			parakeet: "English + 24 European (auto)",
			lead: "none",
		},
		{
			label: "Live typing",
			orukeet: "No",
			parakeet: "Yes (with add-on)",
			lead: "parakeet",
		},
		{
			label: "Default",
			orukeet: "Yes (new installs)",
			parakeet: "Fallback / live-typing base",
			lead: "orukeet",
		},
	],
	footnote:
		"Median key-up-to-paste over 10 dictations each, measured on Apple M3 Pro, on-device.",
};
