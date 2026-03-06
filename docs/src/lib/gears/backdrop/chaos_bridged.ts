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

type BridgeCandidate = {
  gear: DraftGear;
  neighbors: DraftGear[];
  score: number;
};

const PATCH_TEETH = [12, 16, 20, 24, 28];

function centeredOffset(index: number, count: number): number {
  return index - (count - 1) * 0.5;
}

function patchVectors(teeth: number, angle: number) {
  const pitchRadius = pitchRadiusFromTeeth(teeth, HERO_GEAR_CIRCULAR_PITCH);
  const spacing = pitchRadius * 2;
  return {
    spacing,
    u: { x: Math.cos(angle) * spacing, y: Math.sin(angle) * spacing },
    v: { x: Math.cos(angle + Math.PI / 2) * spacing, y: Math.sin(angle + Math.PI / 2) * spacing },
  };
}

function patchCellCenter(patch: Patch, col: number, row: number): Point {
  const { u, v } = patchVectors(patch.teeth, patch.angle);
  const x = patch.center.x + u.x * centeredOffset(col, patch.cols) + v.x * centeredOffset(row, patch.rows);
  const y = patch.center.y + u.y * centeredOffset(col, patch.cols) + v.y * centeredOffset(row, patch.rows);
  return { x, y };
}

function patchMask(patch: Patch, col: number, row: number): boolean {
  const edge = Math.min(col, row, patch.cols - 1 - col, patch.rows - 1 - row);
  if (edge >= 1) return true;

  const wave = Math.sin(col * 1.13 + patch.angle * 1.7 + patch.center.x * 0.005) + Math.cos(row * 1.21 - patch.center.y * 0.006);
  return wave > (edge === 0 ? 0.15 + (1 - patch.density) * 1.3 : -0.5);
}

function bottomContourY(x: number, phase: number): number {
  return 330 + Math.sin(x / 180 + phase) * 20 + Math.sin(x / 76 - phase * 0.6) * 12;
}

export const generateChaosBridgedBackdrop: BackdropGeneratorFn = ({ seed, targetCount = 116 }) => {
  const { random } = createGenerationContext(seed, 0x7b1d9);
  const contourPhase = random() * Math.PI * 2;
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

  const patches: Patch[] = [
    {
      id: "bridge-left",
      teeth: 12,
      cols: 7,
      rows: 5,
      angle: -0.32 + (random() - 0.5) * 0.06,
      center: { x: -170, y: 108 + random() * 22 },
      parity: 0,
      density: 0.93,
    },
    {
      id: "bridge-left-mid",
      teeth: 16,
      cols: 6,
      rows: 4,
      angle: 0.16 + (random() - 0.5) * 0.06,
      center: { x: 340, y: 136 + random() * 20 },
      parity: 1,
      density: 0.9,
    },
    {
      id: "bridge-center",
      teeth: 12,
      cols: 7,
      rows: 5,
      angle: -0.04 + (random() - 0.5) * 0.06,
      center: { x: 860, y: 98 + random() * 18 },
      parity: 0,
      density: 0.95,
    },
    {
      id: "bridge-right-mid",
      teeth: 16,
      cols: 6,
      rows: 4,
      angle: 0.2 + (random() - 0.5) * 0.06,
      center: { x: 1350, y: 128 + random() * 18 },
      parity: 1,
      density: 0.9,
    },
    {
      id: "bridge-right",
      teeth: 12,
      cols: 7,
      rows: 5,
      angle: -0.2 + (random() - 0.5) * 0.06,
      center: { x: 1810, y: 100 + random() * 18 },
      parity: 0,
      density: 0.94,
    },
  ];

  for (const patch of patches) {
    const plannedCells = [] as Array<{ col: number; row: number; center: Point }>;
    for (let row = 0; row < patch.rows; row += 1) {
      for (let col = 0; col < patch.cols; col += 1) {
        if (!patchMask(patch, col, row)) continue;
        plannedCells.push({ col, row, center: patchCellCenter(patch, col, row) });
      }
    }

    plannedCells.sort((left, right) => {
      const leftBias = Math.abs(left.center.x - patch.center.x) + Math.abs(left.center.y - patch.center.y);
      const rightBias = Math.abs(right.center.x - patch.center.x) + Math.abs(right.center.y - patch.center.y);
      return leftBias - rightBias;
    });

    const byCell = new Map<string, DraftGear>();
    for (const cell of plannedCells) {
      if (gears.length >= targetCount) break;
      const key = `${cell.col},${cell.row}`;
      const localNeighbors = [
        byCell.get(`${cell.col - 1},${cell.row}`),
        byCell.get(`${cell.col + 1},${cell.row}`),
        byCell.get(`${cell.col},${cell.row - 1}`),
        byCell.get(`${cell.col},${cell.row + 1}`),
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
      byCell.set(key, candidate);
    }
  }

  let bridgeAttempts = 0;
  while (gears.length < targetCount && bridgeAttempts < 420) {
    bridgeAttempts += 1;
    let best: BridgeCandidate | null = null;

    for (let i = 0; i < gears.length; i += 1) {
      const a = gears[i];
      for (let j = i + 1; j < gears.length; j += 1) {
        const b = gears[j];
        if (a.parity !== b.parity) continue;
        if (patchByGearId.get(a.id) === patchByGearId.get(b.id)) continue;
        if (edgeKeys.has(a.id < b.id ? `${a.id}|${b.id}` : `${b.id}|${a.id}`)) continue;

        const span = dist(a.center, b.center);
        if (span > 320 || span < 40) continue;

        const toothChoices = PATCH_TEETH.filter((teeth) => teeth <= Math.max(a.teeth, b.teeth) + 4);
        for (const teeth of toothChoices) {
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

            const loopBias = verdict.neighbors.length >= 3 ? 180 : 120;
            const contourBias = Math.max(0, 100 - Math.abs(candidate.center.y + candidate.outerRadius - bottomContourY(candidate.center.x, contourPhase))) * 0.35;
            const score = loopBias + verdict.neighbors.length * 70 + contourBias - span * 0.12 + random() * 6;
            if (!best || score > best.score) best = { gear: candidate, neighbors: verdict.neighbors, score };
          }
        }
      }
    }

    if (!best) break;
    registerPlacement(best.gear, best.neighbors, `bridge-${bridgeAttempts}`);
  }

  return { gears, edges };
};
