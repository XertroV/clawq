# Docs Notes

- In `src/components/HeroGearBackdrop.astro`, do not render every backdrop algorithm in dev just to support the debug picker.
- Rendering all algorithms at once makes `/` rebuilds jump from fast to multi-second because every generator and SVG path gets recomputed.
- Keep the page on a single rendered algorithm and let the debug picker fetch/swap the selected backdrop instead.

## llms.txt Maintenance

Two files in `public/`:
- `llms.txt` — spec-compliant index (H1, blockquote summary, H2 link-list sections). Follows the llmstxt.org specification: no headings in body content, H2 sections contain only markdown link lists.
- `llms-full.txt` — full self-knowledge reference with every CLI command, config field/default, tool, channel, endpoint, and setup guide. This is the detailed document clawq uses to understand itself.

When docs content changes (new commands, config fields, channels, tools, setup steps):
- Update `public/llms-full.txt` with the detailed changes.
- Update `public/llms.txt` only if new doc pages are added or the summary needs revision.
- Keep llms-full.txt factual, concise, and oriented toward clawq operating on itself — not a marketing overview.
