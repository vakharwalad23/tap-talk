import { formatCount, useRepoStats } from "./useRepoStats";

interface StarCountProps {
	readonly repoSlug: string;
	readonly fallback: string;
}

export function StarCount({ repoSlug, fallback }: StarCountProps) {
	const stats = useRepoStats(repoSlug);
	return <span>{stats === null ? fallback : formatCount(stats.stars)}</span>;
}
