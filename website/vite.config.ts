import { cloudflare } from "@cloudflare/vite-plugin";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import viteReact from "@vitejs/plugin-react";
import { defineConfig } from "vite";

const siteHost = "https://taptalk.dhruvvakharwala.dev";

export default defineConfig({
	resolve: { tsconfigPaths: true },
	plugins: [
		cloudflare({ viteEnvironment: { name: "ssr" } }),
		tanstackStart({
			// Prerender mode: every route becomes static HTML served as a Cloudflare asset.
			// SSR stays available by flipping this off; the Worker only runs for non-asset paths.
			prerender: {
				enabled: true,
				crawlLinks: true,
				autoSubfolderIndex: true,
				failOnError: true,
			},
			sitemap: { enabled: true, host: siteHost },
			// Route CSS is inlined into the prerendered HTML: one fewer request on first paint.
			server: { build: { inlineCss: true } },
		}),
		viteReact(),
	],
});
