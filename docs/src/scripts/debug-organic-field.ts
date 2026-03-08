import { generateHeroBackdropDraft } from "../lib/gears/backdrop_generation.ts";
import {
  backdropBounds,
  buildSolvedDebugGears,
  buildTrueMeshEdges,
  componentStats,
  DEBUG_TOOTH_TUNING,
} from "../lib/gears/backdrop/debug_spec.ts";
import { buildGearPath } from "../lib/gears/path.ts";

const DEFAULT_SEED = 0x6a11cf;
const DEFAULT_TARGET = 96;
const DEFAULT_WIDTH = 3440;
const DEFAULT_HEIGHT = 900;
const WORLD_VIEWBOX = { minX: -220, minY: -120, width: 3440, height: 900 };

const controls = document.getElementById("organic-field-controls") as HTMLFormElement | null;
const seedInput = document.getElementById("organic-seed-input") as HTMLInputElement | null;
const targetInput = document.getElementById("organic-target-input") as HTMLInputElement | null;
const widthInput = document.getElementById("organic-width-input") as HTMLInputElement | null;
const heightInput = document.getElementById("organic-height-input") as HTMLInputElement | null;
const metricsRoot = document.getElementById("organic-metrics");
const wideMeta = document.getElementById("organic-wide-meta");
const fitMeta = document.getElementById("organic-fit-meta");
const wideSceneRoot = document.getElementById("organic-wide-scene");
const fitSceneRoot = document.getElementById("organic-fit-scene");
const comparisonGrid = document.getElementById("organic-comparison-grid");
const seedRow = document.getElementById("organic-seed-row");

function readInt(value: string | null | undefined, fallback: number): number {
  if (value == null || value === "") return fallback;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function graphStats(result: ReturnType<typeof generateHeroBackdropDraft>) {
  const counts = new Map(result.gears.map((gear) => [gear.id, 0]));
  const adjacency = new Map(result.gears.map((gear) => [gear.id, [] as string[]]));

  for (const edge of result.edges) {
    counts.set(edge.a, (counts.get(edge.a) ?? 0) + 1);
    counts.set(edge.b, (counts.get(edge.b) ?? 0) + 1);
    adjacency.get(edge.a)?.push(edge.b);
    adjacency.get(edge.b)?.push(edge.a);
  }

  let componentCount = 0;
  let largestComponent = 0;
  const seen = new Set<string>();
  for (const gear of result.gears) {
    if (seen.has(gear.id)) continue;
    componentCount += 1;
    let size = 0;
    const stack = [gear.id];
    seen.add(gear.id);
    while (stack.length > 0) {
      const current = stack.pop();
      if (!current) continue;
      size += 1;
      for (const next of adjacency.get(current) ?? []) {
        if (seen.has(next)) continue;
        seen.add(next);
        stack.push(next);
      }
    }
    largestComponent = Math.max(largestComponent, size);
  }

  const richNeighborCount = [...counts.values()].filter((count) => count >= 3).length;
  const leafCount = [...counts.values()].filter((count) => count <= 1).length;
  const cycleRank = result.edges.length - result.gears.length + componentCount;
  return { componentCount, largestComponent, richNeighborCount, leafCount, cycleRank };
}

function occupancyBuckets(result: ReturnType<typeof generateHeroBackdropDraft>, bucketCount = 14): number {
  const xMin = -180;
  const xMax = 1780;
  const width = (xMax - xMin) / bucketCount;
  const occupied = new Set<number>();

  for (const gear of result.gears) {
    const start = Math.max(0, Math.floor((gear.center.x - gear.outerRadius - xMin) / width));
    const end = Math.min(bucketCount - 1, Math.floor((gear.center.x + gear.outerRadius - xMin) / width));
    for (let index = start; index <= end; index += 1) occupied.add(index);
  }

  return occupied.size;
}

function buildVisual(result: ReturnType<typeof generateHeroBackdropDraft>) {
  const solved = buildSolvedDebugGears(result.gears, result.edges);
  const bounds = solved.length > 0 ? backdropBounds(solved, 84) : { minX: 0, minY: 0, width: 100, height: 100 };
  const meshEdges = buildTrueMeshEdges(result.gears, result.edges);
  const stats = graphStats(result);
  const components = componentStats(result.gears, result.edges);
  const spanX =
    result.gears.length > 0
      ? Math.max(...result.gears.map((gear) => gear.center.x + gear.outerRadius)) -
        Math.min(...result.gears.map((gear) => gear.center.x - gear.outerRadius))
      : 0;

  const palette = [
    { line: "rgba(243, 200, 116, 0.76)", fill: "rgba(146, 95, 36, 0.12)" },
    { line: "rgba(112, 193, 199, 0.72)", fill: "rgba(31, 103, 110, 0.1)" },
    { line: "rgba(237, 236, 219, 0.62)", fill: "rgba(113, 111, 92, 0.08)" },
    { line: "rgba(214, 137, 91, 0.72)", fill: "rgba(128, 63, 34, 0.1)" },
  ];

  const visuals = solved
    .slice()
    .sort((a, b) => a.center.y - b.center.y)
    .map((gear, index) => ({
      gear,
      path: buildGearPath(gear, DEBUG_TOOTH_TUNING),
      palette: palette[index % palette.length],
    }));

  return {
    result,
    bounds,
    meshEdges,
    visuals,
    stats,
    components,
    occupancy: occupancyBuckets(result),
    spanX,
  };
}

function metricsMarkup(primary: ReturnType<typeof buildVisual>, seed: number, targetCount: number): string {
  const rows = [
    ["Seed", seed],
    ["Requested gears", targetCount],
    ["Actual gears", primary.result.gears.length],
    ["Edges", primary.result.edges.length],
    ["Cycle rank", primary.stats.cycleRank],
    ["Rich nodes", primary.stats.richNeighborCount],
    ["Leaves", primary.stats.leafCount],
    ["Occupancy", `${primary.occupancy}/14`],
    ["Components", primary.stats.componentCount],
    ["Largest component", primary.stats.largestComponent],
    ["Width span", Math.round(primary.spanX)],
    ["True mesh edges", primary.meshEdges.length],
  ];

  return rows
    .map(
      ([label, value]) => `\n        <div class="metric">\n          <span>${label}</span>\n          <strong>${value}</strong>\n        </div>\n      `,
    )
    .join("");
}

function sceneSvg(visual: ReturnType<typeof buildVisual>, viewBox: { minX: number; minY: number; width: number; height: number }, subtleBand = false): string {
  const meshLines = visual.meshEdges
    .map(
      (edge) => `<line x1="${edge.x1}" y1="${edge.y1}" x2="${edge.x2}" y2="${edge.y2}" class="mesh-line" />`,
    )
    .join("");
  const gears = visual.visuals
    .map(
      ({ gear, path, palette }) => `
        <g transform="translate(${gear.center.x} ${gear.center.y}) rotate(${gear.phaseDeg})">
          <path d="${path}" class="gear-outline" stroke="${palette.line}" fill="${palette.fill}" />
          <circle r="${gear.pitchRadius}" class="pitch-circle" />
          <circle r="${gear.holeRadius}" class="gear-hole" />
        </g>
      `,
    )
    .join("");

  return `
    <svg class="debug-scene ${viewBox === WORLD_VIEWBOX ? "debug-scene--wide" : ""}" viewBox="${viewBox.minX} ${viewBox.minY} ${viewBox.width} ${viewBox.height}" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="organic-field scene">
      <defs>
        <pattern id="organic-grid" width="140" height="140" patternUnits="userSpaceOnUse">
          <path d="M 140 0 L 0 0 0 140" class="grid-line" />
        </pattern>
      </defs>
      <rect x="${viewBox.minX}" y="${viewBox.minY}" width="${viewBox.width}" height="${viewBox.height}" class="bg" />
      <rect x="-180" y="-40" width="1960" height="470" class="hero-band ${subtleBand ? "hero-band--subtle" : ""}" />
      <rect x="${viewBox.minX}" y="${viewBox.minY}" width="${viewBox.width}" height="${viewBox.height}" fill="url(#organic-grid)" opacity="${subtleBand ? "0.35" : "1"}" />
      ${meshLines}
      ${gears}
    </svg>
  `;
}

function comparisonCard(entry: { seed: number } & ReturnType<typeof buildVisual>): string {
  return `
    <article class="panel comparison-card">
      <div class="section-head">
        <div>
          <p class="kicker">Alternate seed</p>
          <h2>${entry.seed}</h2>
        </div>
        <p class="meta">cycles ${entry.stats.cycleRank} • leaves ${entry.stats.leafCount}</p>
      </div>
      ${sceneSvg(entry, WORLD_VIEWBOX, true)}
      <div class="mini-metrics">
        <span>${entry.result.gears.length} gears</span>
        <span>${entry.result.edges.length} edges</span>
        <span>${entry.occupancy}/14 coverage</span>
        <span>${entry.stats.componentCount} comps</span>
      </div>
    </article>
  `;
}

function debugViewbox(width: number, height: number) {
  return {
    minX: WORLD_VIEWBOX.minX,
    minY: WORLD_VIEWBOX.minY,
    width,
    height,
  };
}

function syncSeedButtons(seed: number, targetCount: number): void {
  for (const button of seedRow?.querySelectorAll<HTMLButtonElement>(".seed-chip") ?? []) {
    const buttonSeed = Number(button.dataset.seed);
    button.classList.toggle("active", buttonSeed === seed);
    button.onclick = () => renderFromState(buttonSeed, targetCount, readInt(widthInput?.value, DEFAULT_WIDTH), readInt(heightInput?.value, DEFAULT_HEIGHT), true);
  }
}

function renderFromState(seed: number, targetCount: number, width: number, height: number, pushUrl = false): void {
  const viewbox = debugViewbox(width, height);
  const viewport = { minX: viewbox.minX, minY: viewbox.minY, width, height };
  const primary = buildVisual(generateHeroBackdropDraft({ algorithm: "organic-field", seed, targetCount, viewport }));
  const comparisons = [seed + 1, seed + 2, seed + 3].map((compareSeed) => ({
    seed: compareSeed,
    ...buildVisual(generateHeroBackdropDraft({ algorithm: "organic-field", seed: compareSeed, targetCount, viewport })),
  }));

  if (seedInput) seedInput.value = String(seed);
  if (targetInput) targetInput.value = String(targetCount);
  if (widthInput) widthInput.value = String(width);
  if (heightInput) heightInput.value = String(height);
  if (metricsRoot) metricsRoot.innerHTML = metricsMarkup(primary, seed, targetCount);
  if (wideMeta) wideMeta.textContent = `component sizes: ${primary.components.sizes.join(", ") || "none"}`;
  if (fitMeta) fitMeta.textContent = `bounds: ${Math.round(primary.bounds.width)} x ${Math.round(primary.bounds.height)}`;
  if (wideSceneRoot) wideSceneRoot.innerHTML = sceneSvg(primary, viewbox);
  if (fitSceneRoot) fitSceneRoot.innerHTML = sceneSvg(primary, primary.bounds, true);
  if (comparisonGrid) comparisonGrid.innerHTML = comparisons.map((entry) => comparisonCard(entry)).join("");
  syncSeedButtons(seed, targetCount);
  document.querySelector<HTMLElement>(".gear-background")?.style.setProperty("display", "none");

  if (pushUrl) {
    const url = new URL(window.location.href);
    url.searchParams.set("seed", String(seed));
    url.searchParams.set("targetCount", String(targetCount));
    url.searchParams.set("width", String(width));
    url.searchParams.set("height", String(height));
    history.replaceState({}, "", url);
  }
}

controls?.addEventListener("submit", (event) => {
  event.preventDefault();
  renderFromState(
    readInt(seedInput?.value, DEFAULT_SEED),
    readInt(targetInput?.value, DEFAULT_TARGET),
    readInt(widthInput?.value, DEFAULT_WIDTH),
    readInt(heightInput?.value, DEFAULT_HEIGHT),
    true,
  );
});

const params = new URLSearchParams(window.location.search);
const seed = readInt(params.get("seed"), DEFAULT_SEED);
const targetCount = readInt(params.get("targetCount"), DEFAULT_TARGET);
const width = readInt(params.get("width"), DEFAULT_WIDTH);
const height = readInt(params.get("height"), DEFAULT_HEIGHT);
renderFromState(seed, targetCount, width, height, false);
