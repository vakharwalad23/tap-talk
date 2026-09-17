# ASCII-Only Standards

All committed text is 7-bit ASCII (U+0000 to U+007F), with a single narrow exception for
non-Latin example data (below). This is strict and enforced. It applies to Swift, Rust,
TypeScript, YAML, JSON, shell, Markdown, docs, UI strings, log messages, commit messages,
branch names, tag messages, and file names - the whole repository, `website/` included.

## Why

Source is typed, not auto-formatted. Editors, word processors, and AI tools silently substitute
"typographic" punctuation - a hyphen becomes a dash, a quote becomes a curly quote, three periods
become an ellipsis glyph. That substitution is the defect this rule exists to stop. It is invisible
in most renderings, breaks grep and diffs, and corrupts terminal output and clipboard round-trips.
Do not commit it.

## Banned characters and their ASCII replacement

Referred to by name and codepoint on purpose - the glyphs themselves must never appear in this repo.

| Name (codepoint) | Use instead |
|---|---|
| EM DASH (U+2014) | ` - ` (spaced hyphen) |
| EN DASH (U+2013) | `-` (hyphen), or ` to ` for a numeric range |
| any other dash (U+2010 to U+2015) | `-` |
| LEFT/RIGHT SINGLE QUOTATION MARK (U+2018, U+2019) | `'` (straight apostrophe) |
| LEFT/RIGHT DOUBLE QUOTATION MARK (U+201C, U+201D) | `"` (straight quote) |
| HORIZONTAL ELLIPSIS (U+2026) | `...` (three periods) |
| arrows (U+2190 to U+21FF, e.g. RIGHTWARDS ARROW U+2192) | `->`, `<-`, `=>` |
| NO-BREAK SPACE (U+00A0) | a normal space |
| BULLET (U+2022) and other list glyphs | `-` or `*` in a real Markdown list |
| MINUS SIGN (U+2212) | `-` (hyphen-minus) |
| MIDDLE DOT (U+00B7) | `-`, `.`, or ` / ` |

No emoji anywhere in source, comments, UI strings, or commit messages. Icons are SF Symbols
(app) or inline SVG (website), never emoji.

## The one exception: non-Latin example and demo data

Devanagari (and other non-Latin scripts) are allowed ONLY as the literal content of a genuine
multilingual EXAMPLE or DEMO record - never in identifiers, general prose, comments that explain
code, UI chrome, log lines, or commit messages. As of this writing the exception covers exactly
two files:

- `TapTalk/Services/AppContextService.swift` - the Hindi few-shot romanization example pairs.
- `website/src/content/intelligence.ts` - the spoken-Hindi sample string.

A new, genuine multilingual example inherits this exception; add it to the list above in the same
change. Everything else non-ASCII is a defect.

## Enforcement

Run before every commit and in review. Non-ASCII outside the Devanagari block (U+0900 to U+097F)
is a blocking defect; empty output means clean.

```bash
git ls-files -z -- . ':!:*.png' ':!:*.jpg' ':!:*.jpeg' ':!:*.gif' ':!:*.icns' ':!:*.ico' \
  ':!:*.pdf' ':!:*.zip' ':!:*.woff' ':!:*.woff2' ':!:*.ttf' ':!:*.otf' ':!:*.mp4' ':!:*.mov' \
| xargs -0 perl -CSD -ne 'while(/([^\x00-\x7F])/g){ my $o=ord($1);
    printf("%s:%d U+%04X [%s]\n", $ARGV, $., $o, $1) unless $o >= 0x0900 && $o <= 0x097F }
  close ARGV if eof;'
```

The check exempts the whole Devanagari block as a fast first pass; a reviewer still confirms any
Devanagari it lets through sits in genuine example data (the two files above), not in code or prose.
A commit message or branch name is checked the same way: type only ASCII.
