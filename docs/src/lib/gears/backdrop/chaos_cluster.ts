import { pitchRadiusFromTeeth } from "../solver.ts";
import type { BackdropGeneratorFn, DraftGear, DraftMeshEdge, Point } from "./types.ts";
import {
  HERO_GEAR_CIRCULAR_PITCH,
  VIEWBOX,
  createGenerationContext,
  dist,
  evaluatePlacement,
  getTwoParentMeshedIntersections,
  outerRadiusFromTeeth,
  registerMeshContacts,
  solveNeighborPhaseTurn,
} from "./shared.ts";

type Patch = {
  id: string;
  teeth: number;
  cols: number;
  rows: number;
  angle: number;
  center: Point;
  parity: 0 | 1;
  density: number;
};

type BuiltBackdrop = {
  gears: DraftGear[];
  edges: DraftMeshEdge[];
  edgeKeys: Set<string>;
  contactAnglesByGearId: Map<string, number[]>;
  patchByGearId: Map<string, string>;
};

const PATCH_TEETH = [12, 16, 20, 24, 28];

function centeredOffset(index: number, count: number): number {
  return index - (count - 1) * 0.5;
}

function patchVectors(teeth: number, angle: number) {
  const pitchRadius = pitchRadiusFromTeeth(teeth, HERO_GEAR_CIRCULAR_PITCH);
  const spacing = pitchRadius * 2;
  return {
    u: { x: Math.cos(angle) * spacing, y: Math.sin(angle) * spacing },
    v: { x: Math.cos(angle + Math.PI / 2) * spacing, y: Math.sin(angle + Math.PI / 2) * spacing },
  };
}

function patchCellCenter(patch: Patch, col: number, row: number): Point {
  const { u, v } = patchVectors(patch.teeth, patch.angle);
  return {
    x: patch.center.x + u.x * centeredOffset(col, patch.cols) + v.x * centeredOffset(row, patch.rows),
    y: patch.center.y + u.y * centeredOffset(col, patch.cols) + v.y * centeredOffset(row, patch.rows),
  };
}

function patchMask(patch: Patch, col: number, row: number): boolean {
  const edge = Math.min(col, row, patch.cols - 1 - col, patch.rows - 1 - row);
  if (edge >= 1) return true;
  const wave = Math.sin(col * 1.07 + patch.center.x * 0.004) + Math.cos(row * 1.19 - patch.center.y * 0.005 + patch.angle * 3);
  return wave > 0.05 - patch.density * 0.85;
}

function patchScoreDelta(transform: { dx: number; dy: number; dAngle: number }): number {
  return Math.abs(transform.dx) * 0.18 + Math.abs(transform.dy) * 0.18 + Math.abs(transform.dAngle) * 220;
}

export const generateChaosClusterBackdrop: BackdropGeneratorFn = ({ seed, targetCount = 116 }) => {
  const { random } = createGenerationContext(seed, 0x7b213);

  let patches: Patch[] = [
    {
      id: "cluster-left",
      teeth: 12,
      cols: 7,
      rows: 5,
      angle: -0.28 + (random() - 0.5) * 0.06,
      center: { x: -150, y: 108 + random() * 18 },
      parity: 0,
      density: 0.94,
    },
    {
      id: "cluster-left-mid",
      teeth: 16,
      cols: 6,
      rows: 4,
      angle: 0.1 + (random() - 0.5) * 0.06,
      center: { x: 360, y: 126 + random() * 22 },
      parity: 1,
      density: 0.92,
    },
    {
      id: "cluster-center",
      teeth: 12,
      cols: 7,
      rows: 5,
      angle: -0.08 + (random() - 0.5) * 0.06,
      center: { x: 870, y: 96 + random() * 24 },
      parity: 0,
      density: 0.95,
    },
    {
      id: "cluster-right-mid",
      teeth: 16,
      cols: 6,
      rows: 4,
      angle: 0.22 + (random() - 0.5) * 0.06,
      center: { x: 1340, y: 124 + random() * 20 },
      parity: 1,
      density: 0.91,
    },
    {
      id: "cluster-right",
      teeth: 12,
      cols: 7,
      rows: 5,
      angle: -0.18 + (random() - 0.5) * 0.06,
      center: { x: 1800, y: 102 + random() * 18 },
      parity: 0,
      density: 0.94,
    },
  ];

  function buildBackdrop(activePatches: Patch[]): BuiltBackdrop {
    const gears: DraftGear[] = [];
    const edges: DraftMeshEdge[] = [];
    const edgeKeys = new Set<string>();
    const contactAnglesByGearId = new Map<string, number[]>();
    const patchByGearId = new Map<string, string>();

    function registerPlacement(gear: DraftGear, neighbors: DraftGear[], patchId: string): void {
      gears.push(gear);
      patchByGearId.set(gear.id, patchId);
      registerMeshContacts({ gear, neighbors, contactAnglesByGearId, edges, edgeKeys });
    }

    for (const patch of activePatches) {
      const cells = [] as Array<{ col: number; row: number; center: Point }>;
      for (let row = 0; row < patch.rows; row += 1) {
        for (let col = 0; col < patch.cols; col += 1) {
          if (!patchMask(patch, col, row)) continue;
          cells.push({ col, row, center: patchCellCenter(patch, col, row) });
        }
      }

      cells.sort((left, right) => {
        const leftBias = Math.abs(left.center.x - patch.center.x) + Math.abs(left.center.y - patch.center.y);
        const rightBias = Math.abs(right.center.x - patch.center.x) + Math.abs(right.center.y - patch.center.y);
        return leftBias - rightBias;
      });

      const placed = new Map<string, DraftGear>();
      for (const cell of cells) {
        if (gears.length >= targetCount) break;
        const localNeighbors = [
          placed.get(`${cell.col - 1},${cell.row}`),
          placed.get(`${cell.col + 1},${cell.row}`),
          placed.get(`${cell.col},${cell.row - 1}`),
          placed.get(`${cell.col},${cell.row + 1}`),
        ].filter((gear): gear is DraftGear => Boolean(gear));

        const pitchRadius = pitchRadiusFromTeeth(patch.teeth, HERO_GEAR_CIRCULAR_PITCH);
        const candidate: DraftGear = {
          id: `hero-g${gears.length}`,
          teeth: patch.teeth,
          pitchRadius,
          outerRadius: outerRadiusFromTeeth(patch.teeth),
          center: cell.center,
          phaseTurn:
            localNeighbors[0] == null
              ? 0
              : solveNeighborPhaseTurn({
                  currentTeeth: localNeighbors[0].teeth,
                  neighborTeeth: patch.teeth,
                  currentTurn: localNeighbors[0].phaseTurn ?? 0,
                  contactAngleCurrentToNeighbor: Math.atan2(
                    cell.center.y - localNeighbors[0].center.y,
                    cell.center.x - localNeighbors[0].center.x
                  ),
                }),
          parity: ((patch.parity + cell.col + cell.row) % 2) as 0 | 1,
          parentId: localNeighbors[0]?.id,
          appearIndex: gears.length,
        };

        const verdict = evaluatePlacement(candidate, gears, contactAnglesByGearId, localNeighbors[0]?.id, true);
        if (!verdict.ok) continue;
        registerPlacement(candidate, verdict.neighbors, patch.id);
        placed.set(`${cell.col},${cell.row}`, candidate);
      }
    }

    return { gears, edges, edgeKeys, contactAnglesByGearId, patchByGearId };
  }

  function bridgeOpportunityScore(backdrop: BuiltBackdrop): number {
    let score = 0;
    const { gears, patchByGearId, contactAnglesByGearId } = backdrop;

    for (let i = 0; i < gears.length; i += 1) {
      const a = gears[i];
      for (let j = i + 1; j < gears.length; j += 1) {
        const b = gears[j];
        if (a.parity !== b.parity) continue;
        if (patchByGearId.get(a.id) === patchByGearId.get(b.id)) continue;
        const span = dist(a.center, b.center);
        if (span < 80 || span > 320) continue;

        let bestNeighbors = 0;
        for (const teeth of PATCH_TEETH) {
          const pitchRadius = pitchRadiusFromTeeth(teeth, HERO_GEAR_CIRCULAR_PITCH);
          for (const option of getTwoParentMeshedIntersections({ parentA: a, parentB: b, teeth })) {
            const candidate: DraftGear = {
              id: "probe",
              teeth,
              pitchRadius,
              outerRadius: outerRadiusFromTeeth(teeth),
              center: option.center,
              phaseTurn: solveNeighborPhaseTurn({
                currentTeeth: a.teeth,
                neighborTeeth: teeth,
                currentTurn: a.phaseTurn ?? 0,
                contactAngleCurrentToNeighbor: option.contactAngleFromA,
              }),
              parity: (a.parity === 0 ? 1 : 0) as 0 | 1,
              parentId: a.id,
              appearIndex: 0,
            };
            const verdict = evaluatePlacement(candidate, gears, contactAnglesByGearId, undefined, true);
            if (!verdict.ok || !verdict.neighbors.some((neighbor) => neighbor.id === a.id) || !verdict.neighbors.some((neighbor) => neighbor.id === b.id)) {
              continue;
            }
            bestNeighbors = Math.max(bestNeighbors, verdict.neighbors.length);
          }
        }

        if (bestNeighbors >= 2) score += bestNeighbors >= 3 ? 3 : 1;
      }
    }

    return score;
  }

  for (let pass = 0; pass < 2; pass += 1) {
    for (let index = 0; index < patches.length; index += 1) {
      const patch = patches[index];
      let bestPatch = patch;
      let bestScore = -Infinity;
      const transforms = [
        { dx: 0, dy: 0, dAngle: 0 },
        { dx: -12, dy: 0, dAngle: 0 },
        { dx: 12, dy: 0, dAngle: 0 },
        { dx: 0, dy: -8, dAngle: 0 },
        { dx: 0, dy: 8, dAngle: 0 },
        { dx: 0, dy: 0, dAngle: -0.04 },
        { dx: 0, dy: 0, dAngle: 0.04 },
        { dx: -12, dy: -8, dAngle: -0.04 },
        { dx: 12, dy: 8, dAngle: 0.04 },
      ];

      for (const transform of transforms) {
        const candidatePatch = {
          ...patch,
          center: { x: patch.center.x + transform.dx, y: patch.center.y + transform.dy },
          angle: patch.angle + transform.dAngle,
        };
        const trialPatches = patches.slice();
        trialPatches[index] = candidatePatch;
        const backdrop = buildBackdrop(trialPatches);
        const score = bridgeOpportunityScore(backdrop) - patchScoreDelta(transform);
        if (score > bestScore) {
          bestScore = score;
          bestPatch = candidatePatch;
        }
      }

      patches[index] = bestPatch;
    }
  }

  const { gears, edges, edgeKeys, contactAnglesByGearId, patchByGearId } = buildBackdrop(patches);

  function registerPlacement(gear: DraftGear, neighbors: DraftGear[], patchId: string): void {
    gears.push(gear);
    patchByGearId.set(gear.id, patchId);
    registerMeshContacts({ gear, neighbors, contactAnglesByGearId, edges, edgeKeys });
  }

  let attempts = 0;
  while (gears.length < targetCount && attempts < 320) {
    attempts += 1;
    let best: { gear: DraftGear; neighbors: DraftGear[]; score: number } | null = null;

    for (let i = 0; i < gears.length; i += 1) {
      const a = gears[i];
      for (let j = i + 1; j < gears.length; j += 1) {
        const b = gears[j];
        if (a.parity !== b.parity) continue;
        if (patchByGearId.get(a.id) === patchByGearId.get(b.id)) continue;
        if (dist(a.center, b.center) > 320) continue;

        for (const teeth of PATCH_TEETH) {
          const pitchRadius = pitchRadiusFromTeeth(teeth, HERO_GEAR_CIRCULAR_PITCH);
          for (const option of getTwoParentMeshedIntersections({ parentA: a, parentB: b, teeth })) {
            const candidate: DraftGear = {
              id: `hero-g${gears.length}`,
              teeth,
              pitchRadius,
              outerRadius: outerRadiusFromTeeth(teeth),
              center: option.center,
              phaseTurn: solveNeighborPhaseTurn({
                currentTeeth: a.teeth,
                neighborTeeth: teeth,
                currentTurn: a.phaseTurn ?? 0,
                contactAngleCurrentToNeighbor: option.contactAngleFromA,
              }),
              parity: (a.parity === 0 ? 1 : 0) as 0 | 1,
              parentId: a.id,
              appearIndex: gears.length,
            };
            const verdict = evaluatePlacement(candidate, gears, contactAnglesByGearId, undefined, true);
            if (!verdict.ok || verdict.neighbors.length < 2) continue;
            if (!verdict.neighbors.some((neighbor) => neighbor.id === a.id)) continue;
            if (!verdict.neighbors.some((neighbor) => neighbor.id === b.id)) continue;

            const score = verdict.neighbors.length * 90 - dist(a.center, b.center) * 0.1 + random() * 4;
            if (!best || score > best.score) best = { gear: candidate, neighbors: verdict.neighbors, score };
          }
        }
      }
    }

    if (!best) break;
    registerPlacement(best.gear, best.neighbors, `bridge-${attempts}`);
  }

  return { gears, edges };
};
