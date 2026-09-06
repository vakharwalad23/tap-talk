import { useEffect, useState } from "react";

export interface RepoStats {
	readonly stars: number;
	readonly forks: number;
	readonly issues: number;
}

const CACHE_KEY = "taptalk:repo";
const CACHE_MS = 60 * 60 * 1000;

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null;
}

function toStats(value: unknown): RepoStats | null {
	if (!isRecord(value)) return null;
	const {
		stargazers_count: stars,
		forks_count: forks,
		open_issues_count: issues,
	} = value;
	if (
		typeof stars !== "number" ||
		typeof forks !== "number" ||
		typeof issues !== "number"
	)
		return null;
	return { stars, forks, issues };
}

function readCache(): RepoStats | null {
	try {
		const raw = sessionStorage.getItem(CACHE_KEY);
		if (raw === null) return null;
		const parsed: unknown = JSON.parse(raw);
		if (!isRecord(parsed) || typeof parsed.at !== "number") return null;
		if (Date.now() - parsed.at > CACHE_MS) return null;
		return toStats(parsed.stats);
	} catch {
		return null;
	}
}

function writeCache(stats: RepoStats): void {
	try {
		sessionStorage.setItem(
			CACHE_KEY,
			JSON.stringify({ stats, at: Date.now() }),
		);
	} catch {
		// Storage can be unavailable in private windows; the numbers are decorative.
	}
}

let inflight: Promise<RepoStats | null> | null = null;

// One request per page load, shared by every component that shows repo numbers.
function load(repoSlug: string): Promise<RepoStats | null> {
	if (inflight === null) {
		inflight = fetch(`https://api.github.com/repos/${repoSlug}`, {
			headers: { Accept: "application/vnd.github+json" },
		})
			.then((response) => (response.ok ? response.json() : null))
			.then((data: unknown) => {
				const stats = toStats(data);
				if (stats !== null) writeCache(stats);
				return stats;
			})
			.catch(() => null);
	}
	return inflight;
}

export function useRepoStats(repoSlug: string): RepoStats | null {
	const [stats, setStats] = useState<RepoStats | null>(null);

	useEffect(() => {
		const cached = readCache();
		if (cached !== null) {
			setStats(cached);
			return;
		}
		let cancelled = false;
		void load(repoSlug).then((result) => {
			if (!cancelled && result !== null) setStats(result);
		});
		return () => {
			cancelled = true;
		};
	}, [repoSlug]);

	return stats;
}

const compact = new Intl.NumberFormat("en", {
	notation: "compact",
	maximumFractionDigits: 1,
});

export function formatCount(value: number): string {
	return compact.format(value);
}
