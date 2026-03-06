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
};

type BuiltBackdrop = {
  gears: DraftGear[];
  edges: DraftMeshEdge[];
  edgeKeys: Set<string>;
  contactAnglesByGearId: Map<string, number[]>;
  patchByGearId: Map<string, string>;
};

const PATCH_TEETH = [12, 16, 20, 24];

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

function cavityMask(patch: Patch, col: number, row: number): boolean {
  const edge = Math.min(col, row, patch.cols - 1 - col, patch.rows - 1 - row);
  if (edge === 0) return true;
  if (edge >= 2) {
    const holeWave = Math.sin(col * 1.11 + patch.center.x * 0.004) + Math.cos(row * 1.09 - patch.center.y * 0.005);
    return holeWave > -0.65;
  }

  const ringWave = Math.sin(col * 1.3 + patch.center.x * 0.004) + Math.cos(row * 1.1 - patch.center.y * 0.006);
  return ringWave > -0.35;
}

function patchShiftPenalty(transform: { dx: number; dy: number; dAngle: number }): number {
  return Math.abs(transform.dx) * 0.12 + Math.abs(transform.dy) * 0.12 + Math.abs(transform.dAngle) * 180;
}

export const generateChaosCavityBackdrop: BackdropGeneratorFn = ({ seed, targetCount = 108 }) => {
  const { random } = createGenerationContext(seed, 0x7b229);

  let patches: Patch[] = Array.from({ length: 8 }, (_, index) => ({
    id: `cavity-${index}`,
    teeth: PATCH_TEETH[index % PATCH_TEETH.length],
    cols: 5 + (index % 3),
    rows: 5 + ((index + 1) % 2),
    angle: -0.48 + index * 0.11 + (random() - 0.5) * 0.1,
    center: {
      x: -120 + (VIEWBOX.width + 240) * (index / 7) + (random() - 0.5) * 46,
      y: 76 + (index % 3) * 32 + random() * 42,
    },
    parity: (index % 2) as 0 | 1,
  }));

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
          if (!cavityMask(patch, col, row)) continue;
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
        const samePatch = patchByGearId.get(a.id) === patchByGearId.get(b.id);
        const span = dist(a.center, b.center);
        if (span < 55 || span > 280) continue;
        if (samePatch && span < Math.min(a.pitchRadius, b.pitchRadius) * 3.2) continue;

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
            if (!verdict.ok) continue;
            bestNeighbors = Math.max(bestNeighbors, verdict.neighbors.length);
          }
        }

        if (bestNeighbors >= 2) score += bestNeighbors >= 3 ? 4 : 1;
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
        { dx: -10, dy: 0, dAngle: 0 },
        { dx: 10, dy: 0, dAngle: 0 },
        { dx: 0, dy: -8, dAngle: 0 },
        { dx: 0, dy: 8, dAngle: 0 },
        { dx: 0, dy: 0, dAngle: -0.04 },
        { dx: 0, dy: 0, dAngle: 0.04 },
        { dx: -10, dy: -8, dAngle: -0.04 },
        { dx: 10, dy: 8, dAngle: 0.04 },
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
        const score = bridgeOpportunityScore(backdrop) - patchShiftPenalty(transform);
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
  while (gears.length < targetCount && attempts < 360) {
    attempts += 1;
    let best: { gear: DraftGear; neighbors: DraftGear[]; score: number } | null = null;

    for (let i = 0; i < gears.length; i += 1) {
      const a = gears[i];
      for (let j = i + 1; j < gears.length; j += 1) {
        const b = gears[j];
        if (a.parity !== b.parity) continue;
        const samePatch = patchByGearId.get(a.id) === patchByGearId.get(b.id);
        const span = dist(a.center, b.center);
        if (span < 45 || span > 280) continue;
        if (samePatch && span < Math.min(a.pitchRadius, b.pitchRadius) * 3.2) continue;

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
            const loopBonus = verdict.neighbors.length >= 3 ? 140 : 0;
            const samePatchBonus = samePatch ? 24 : 0;
            const score = verdict.neighbors.length * 145 + loopBonus + samePatchBonus - span * 0.07 + random() * 4;
            if (!best || score > best.score) best = { gear: candidate, neighbors: verdict.neighbors, score };
          }
        }
      }
    }

    if (!best) break;
    registerPlacement(best.gear, best.neighbors, `stitch-${attempts}`);
  }

  return { gears, edges };
};
