import { useEffect, useState } from "react";

// Reports which of the given section ids currently crosses a band around the upper third of
// the viewport. Sections without a nav entry are mapped to the nearest one by the caller.
export function useScrollSpy(ids: readonly string[]): string | null {
	const [active, setActive] = useState<string | null>(null);

	useEffect(() => {
		const sections = ids
			.map((id) => document.getElementById(id))
			.filter((element): element is HTMLElement => element !== null);
		if (sections.length === 0) return;

		const visible = new Set<string>();
		const observer = new IntersectionObserver(
			(entries) => {
				for (const entry of entries) {
					if (entry.isIntersecting) visible.add(entry.target.id);
					else visible.delete(entry.target.id);
				}
				const next = ids.find((id) => visible.has(id)) ?? null;
				if (next !== null) setActive(next);
			},
			{ rootMargin: "-30% 0px -55% 0px", threshold: 0 },
		);
		for (const section of sections) observer.observe(section);
		return () => observer.disconnect();
	}, [ids]);

	return active;
}
