import { pitchRadiusFromTeeth } from "../solver.ts";
import type { BackdropGeneratorFn, DraftGear, DraftMeshEdge, Point } from "./types.ts";
import {
  HERO_GEAR_CIRCULAR_PITCH,
  VIEWBOX,
  createGenerationContext,
  evaluatePlacement,
  outerRadiusFromTeeth,
  solveNeighborPhaseTurn,
} from "./shared.ts";

type GridCoord = { gx: number; gy: number };

const RING_WEB_TEETH = 16;
const OUTER_GRID_X = 4;
const OUTER_GRID_Y = 2;

function coordKey({ gx, gy }: GridCoord): string {
  return `${gx},${gy}`;
}

function gridToPoint(origin: Point, spacing: number, { gx, gy }: GridCoord): Point {
  return {
    x: origin.x + gx * spacing,
    y: origin.y + gy * spacing,
  };
}

function neighborsOf(coord: GridCoord): GridCoord[] {
  return [
    { gx: coord.gx + 1, gy: coord.gy },
    { gx: coord.gx - 1, gy: coord.gy },
    { gx: coord.gx, gy: coord.gy + 1 },
    { gx: coord.gx, gy: coord.gy - 1 },
  ];
}

export const generateRingWebBackdrop: BackdropGeneratorFn = ({ seed, targetCount = 45 }) => {
  const { random } = createGenerationContext(seed, 0x51a9c);
  const gears: DraftGear[] = [];
  const edges: DraftMeshEdge[] = [];
  const edgeKeys = new Set<string>();
  const contactAnglesByGearId = new Map<string, number[]>();
  const gearByCoordKey = new Map<string, DraftGear>();

  const pitchRadius = pitchRadiusFromTeeth(RING_WEB_TEETH, HERO_GEAR_CIRCULAR_PITCH);
  const spacing = pitchRadius * 2;
  const center = { x: VIEWBOX.width * 0.5, y: 230 };

  function addEdge(a: string, b: string): void {
    const key = a < b ? `${a}|${b}` : `${b}|${a}`;
    if (edgeKeys.has(key)) return;
    edgeKeys.add(key);
    edges.push({ a, b });
  }

  function registerContactAngles(gear: DraftGear, neighbors: DraftGear[]): void {
    if (!contactAnglesByGearId.has(gear.id)) contactAnglesByGearId.set(gear.id, []);
    const gearContacts = contactAnglesByGearId.get(gear.id)!;

    for (const neighbor of neighbors) {
      gearContacts.push(Math.atan2(neighbor.center.y - gear.center.y, neighbor.center.x - gear.center.x));

      if (!contactAnglesByGearId.has(neighbor.id)) contactAnglesByGearId.set(neighbor.id, []);
      const neighborContacts = contactAnglesByGearId.get(neighbor.id)!;
      neighborContacts.push(Math.atan2(gear.center.y - neighbor.center.y, gear.center.x - neighbor.center.x));

      addEdge(gear.id, neighbor.id);
    }
  }

  function shell(coord: GridCoord): number {
    return Math.max(Math.ceil(Math.abs(coord.gx) / 2), Math.abs(coord.gy));
  }

  const desiredCoords: GridCoord[] = [];
  for (let gy = -OUTER_GRID_Y; gy <= OUTER_GRID_Y; gy += 1) {
    for (let gx = -OUTER_GRID_X; gx <= OUTER_GRID_X; gx += 1) {
      const coord = { gx, gy };
      if (shell(coord) <= 2) desiredCoords.push(coord);
    }
  }

  const desiredCoordKeys = new Set(desiredCoords.map(coordKey));
  const traversalDirs =
    random() < 0.5
      ? [
          { gx: 1, gy: 0 },
          { gx: 0, gy: 1 },
          { gx: -1, gy: 0 },
          { gx: 0, gy: -1 },
        ]
      : [
          { gx: 0, gy: 1 },
          { gx: 1, gy: 0 },
          { gx: 0, gy: -1 },
          { gx: -1, gy: 0 },
        ];

  const queue: GridCoord[] = [{ gx: 0, gy: 0 }];
  const seen = new Set<string>([coordKey(queue[0])]);
  const orderedCoords: GridCoord[] = [];

  while (queue.length > 0) {
    const current = queue.shift()!;
    orderedCoords.push(current);

    for (const dir of traversalDirs) {
      const next = { gx: current.gx + dir.gx, gy: current.gy + dir.gy };
      const key = coordKey(next);
      if (!desiredCoordKeys.has(key) || seen.has(key)) continue;
      seen.add(key);
      queue.push(next);
    }
  }

  const cappedCoords = orderedCoords.slice(0, Math.min(targetCount, orderedCoords.length));

  for (const coord of cappedCoords) {
    const point = gridToPoint(center, spacing, coord);
    const neighborGears = neighborsOf(coord)
      .map((neighbor) => gearByCoordKey.get(coordKey(neighbor)))
      .filter((gear): gear is DraftGear => Boolean(gear));

    const parent = neighborGears[0];
    const phaseTurn =
      parent === undefined
        ? 0
        : solveNeighborPhaseTurn({
            currentTeeth: parent.teeth,
            neighborTeeth: RING_WEB_TEETH,
            currentTurn: parent.phaseTurn ?? 0,
            contactAngleCurrentToNeighbor: Math.atan2(point.y - parent.center.y, point.x - parent.center.x),
          });

    const candidate: DraftGear = {
      id: `hero-g${gears.length}`,
      teeth: RING_WEB_TEETH,
      pitchRadius,
      outerRadius: outerRadiusFromTeeth(RING_WEB_TEETH),
      center: point,
      phaseTurn,
      parity: Math.abs(coord.gx + coord.gy) % 2 === 0 ? 0 : 1,
      parentId: parent?.id,
      appearIndex: gears.length,
    };

    const verdict = evaluatePlacement(candidate, gears, contactAnglesByGearId, parent?.id);
    if (!verdict.ok) continue;

    gears.push(candidate);
    gearByCoordKey.set(coordKey(coord), candidate);
    registerContactAngles(candidate, verdict.neighbors);
  }

  return { gears, edges };
};
