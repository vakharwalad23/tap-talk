import { createRootRoute, HeadContent, Scripts } from "@tanstack/react-router";
import type { ReactNode } from "react";
import { site } from "#/content/site";
import { jsonLdScripts } from "#/seo/jsonld";
import "#/styles/global.css";

const ogImage = `${site.url}${site.ogImagePath}`;
const canonical = `${site.url}/`;

export const Route = createRootRoute({
	head: () => ({
		meta: [
			{ charSet: "utf-8" },
			{ name: "viewport", content: "width=device-width, initial-scale=1" },
			{ title: site.title },
			{ name: "description", content: site.description },
			{ name: "robots", content: "index, follow, max-image-preview:large" },
			{ name: "author", content: site.authorName },
			{
				name: "theme-color",
				media: "(prefers-color-scheme: light)",
				content: "#f4f3f1",
			},
			{
				name: "theme-color",
				media: "(prefers-color-scheme: dark)",
				content: "#17171a",
			},
			{ property: "og:type", content: "website" },
			{ property: "og:locale", content: "en_US" },
			{ property: "og:site_name", content: site.name },
			{ property: "og:url", content: canonical },
			{ property: "og:title", content: site.title },
			{ property: "og:description", content: site.description },
			{ property: "og:image", content: ogImage },
			{ property: "og:image:width", content: "1200" },
			{ property: "og:image:height", content: "630" },
			{
				property: "og:image:alt",
				content: "TapTalk, free on-device dictation for Mac",
			},
			{ name: "twitter:card", content: "summary_large_image" },
			{ name: "twitter:title", content: site.title },
			{ name: "twitter:description", content: site.description },
			{ name: "twitter:image", content: ogImage },
		],
		links: [
			{ rel: "canonical", href: canonical },
			{
				rel: "icon",
				type: "image/png",
				sizes: "32x32",
				href: "/favicon-32.png",
			},
			{
				rel: "icon",
				type: "image/png",
				sizes: "192x192",
				href: "/icon-192.png",
			},
			{ rel: "apple-touch-icon", href: "/apple-touch-icon.png" },
			{ rel: "sitemap", type: "application/xml", href: "/sitemap.xml" },
		],
		scripts: [
			// Flags JS availability before first paint so reveal animations never hide content.
			{ children: "document.documentElement.classList.add('js')" },
			...jsonLdScripts(),
		],
	}),
	shellComponent: RootDocument,
});

function RootDocument({ children }: { readonly children: ReactNode }) {
	return (
		<html lang="en">
			<head>
				<HeadContent />
			</head>
			<body>
				{children}
				<Scripts />
			</body>
		</html>
	);
}
