# Docs Notes

- In `src/components/HeroGearBackdrop.astro`, do not render every backdrop algorithm in dev just to support the debug picker.
- Rendering all algorithms at once makes `/` rebuilds jump from fast to multi-second because every generator and SVG path gets recomputed.
- Keep the page on a single rendered algorithm and let the debug picker fetch/swap the selected backdrop instead.
