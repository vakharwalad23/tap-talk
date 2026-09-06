# TapTalk website

The marketing site for TapTalk, served at https://taptalk.dhruvvakharwala.dev.

TanStack Start in prerender mode: the single route is rendered to static HTML at build time and
served as a Cloudflare static asset. The Worker only runs for paths that are not assets, so SSR is
one config flip away if the site ever needs it.

## Commands

```bash
pnpm install
pnpm dev         # http://localhost:3000
pnpm check       # biome lint and format check
pnpm typecheck   # tsc --noEmit
pnpm build       # prerender into dist/
pnpm preview     # serve the built output locally
pnpm run deploy  # check, typecheck, build, then wrangler deploy
```

Use `pnpm run deploy`, not `pnpm deploy`: the bare form is pnpm's own workspace command.

## Layout

- `src/content/` - all copy and data as typed objects. Sections and JSON-LD render from the same source.
- `src/components/sections/` - one component per page section.
- `src/components/interactive/` - the live pill, the flow diagram, and other client-only pieces.
- `src/components/replicas/` - the app's own screens rebuilt in HTML and CSS.
- `src/seo/` - structured data builders.
- `src/styles/` - design tokens and the global stylesheet. Components use CSS Modules.
- `public/` - icons, `robots.txt`, `llms.txt`, and Cloudflare `_headers`.

Rendered copy is ASCII only, apart from the Hindi demo. The rules that govern this folder live in
`../.claude/rules/website.md`.

## Deploy

`wrangler.jsonc` names the Worker `taptalk-website`. Authenticate once with `wrangler login`, then
`pnpm run deploy`. The custom domain is configured as a route in `wrangler.jsonc`.
