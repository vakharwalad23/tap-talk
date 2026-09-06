import { useEffect } from "react";

const FALLBACK_MS = 6000;

// Marks [data-reveal] elements as shown when they scroll into view. The hidden initial state is
// scoped to html.js in global.css, so content is visible without JavaScript. A timer reveals
// everything regardless, so the effect can never hide content from a reader or a crawler.
export function useReveal(): void {
	useEffect(() => {
		const elements = document.querySelectorAll<HTMLElement>("[data-reveal]");
		const revealAll = () => {
			for (const element of elements) element.setAttribute("data-shown", "");
		};
		if (!("IntersectionObserver" in window)) {
			revealAll();
			return;
		}
		const fallback = window.setTimeout(revealAll, FALLBACK_MS);
		const observer = new IntersectionObserver(
			(entries) => {
				for (const entry of entries) {
					if (!entry.isIntersecting) continue;
					entry.target.setAttribute("data-shown", "");
					observer.unobserve(entry.target);
				}
			},
			{ rootMargin: "0px 0px -8% 0px", threshold: 0.08 },
		);
		for (const element of elements) observer.observe(element);
		return () => {
			observer.disconnect();
			window.clearTimeout(fallback);
		};
	}, []);
}
