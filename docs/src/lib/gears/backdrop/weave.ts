import { pitchRadiusFromTeeth } from "../solver.ts";
import type { BackdropGeneratorFn, DraftGear, DraftMeshEdge } from "./types.ts";
import {
  HERO_GEAR_CIRCULAR_PITCH,
  VIEWBOX,
  Y_MAX,
  Y_MIN,
  createGenerationContext,
  evaluatePlacement,
  outerRadiusFromTeeth,
  solveNeighborPhaseTurn,
} from "./shared.ts";

type Cell = { col: number; row: number };

const WEAVE_TEETH = 16;
const GRID_CENTER = { x: VIEWBOX.width * 0.5, y: 230 };

export const generateWeaveBackdrop: BackdropGeneratorFn = ({ seed, targetCount = 90 }) => {
  const { random } = createGenerationContext(seed, 0x51a9e);
  const gears: DraftGear[] = [];
  const edges: DraftMeshEdge[] = [];
  const gearByCell = new Map<string, DraftGear>();
  const contactAnglesByGearId = new Map<string, number[]>();
  const edgeKeys = new Set<string>();

  const pitchRadius = pitchRadiusFromTeeth(WEAVE_TEETH, HERO_GEAR_CIRCULAR_PITCH);
  const outerRadius = outerRadiusFromTeeth(WEAVE_TEETH);
  const spacing = pitchRadius * 2;
  const colSignBias = random() < 0.5 ? -1 : 1;
  const rowSignBias = random() < 0.5 ? -1 : 1;

  function cellKey(cell: Cell): string {
    return `${cell.col},${cell.row}`;
  }

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
      const angleFromGear = Math.atan2(neighbor.center.y - gear.center.y, neighbor.center.x - gear.center.x);
      gearContacts.push(angleFromGear);

      if (!contactAnglesByGearId.has(neighbor.id)) contactAnglesByGearId.set(neighbor.id, []);
      const neighborContacts = contactAnglesByGearId.get(neighbor.id)!;
      const angleFromNeighbor = Math.atan2(gear.center.y - neighbor.center.y, gear.center.x - neighbor.center.x);
      neighborContacts.push(angleFromNeighbor);

      addEdge(gear.id, neighbor.id);
    }
  }

  function cellCenter(cell: Cell) {
    return {
      x: GRID_CENTER.x + cell.col * spacing,
      y: GRID_CENTER.y + cell.row * spacing,
    };
  }

  function buildCells(): Cell[] {
    const minCol = Math.ceil((-320 - GRID_CENTER.x) / spacing);
    const maxCol = Math.floor((VIEWBOX.width + 320 - GRID_CENTER.x) / spacing);
    const minRow = Math.ceil((Y_MIN + 18 - GRID_CENTER.y) / spacing);
    const maxRow = Math.floor((Y_MAX - 18 - GRID_CENTER.y) / spacing);
    const cells: Cell[] = [];

    for (let row = minRow; row <= maxRow; row += 1) {
      for (let col = minCol; col <= maxCol; col += 1) {
        cells.push({ col, row });
      }
    }

    return cells.sort((a, b) => {
      const signRank = (value: number, preferredSign: number) => {
        if (value === 0) return 0;
        return Math.sign(value) === preferredSign ? -1 : 1;
      };
      const ringDelta = Math.abs(a.col) + Math.abs(a.row) - (Math.abs(b.col) + Math.abs(b.row));
      if (ringDelta !== 0) return ringDelta;

      const coverageBiasA = Math.abs(a.col) * 3 + Math.abs(a.row) * 2;
      const coverageBiasB = Math.abs(b.col) * 3 + Math.abs(b.row) * 2;
      if (coverageBiasA !== coverageBiasB) return coverageBiasA - coverageBiasB;

      const colSignDelta = signRank(a.col, colSignBias) - signRank(b.col, colSignBias);
      if (colSignDelta !== 0) return colSignDelta;

      const rowSignDelta = signRank(a.row, rowSignBias) - signRank(b.row, rowSignBias);
      if (rowSignDelta !== 0) return rowSignDelta;

      if (a.col !== b.col) return a.col - b.col;
      return a.row - b.row;
    });
  }

  function getPlacedNeighbors(cell: Cell): DraftGear[] {
    const orderedCells: Cell[] = [];

    if (cell.col !== 0) orderedCells.push({ col: cell.col - Math.sign(cell.col), row: cell.row });
    if (cell.row !== 0) orderedCells.push({ col: cell.col, row: cell.row - Math.sign(cell.row) });
    orderedCells.push(
      { col: cell.col - 1, row: cell.row },
      { col: cell.col + 1, row: cell.row },
      { col: cell.col, row: cell.row - 1 },
      { col: cell.col, row: cell.row + 1 }
    );

    const seen = new Set<string>();
    const neighbors: DraftGear[] = [];
    for (const neighborCell of orderedCells) {
      const key = cellKey(neighborCell);
      if (seen.has(key)) continue;
      seen.add(key);

      const gear = gearByCell.get(key);
      if (gear) neighbors.push(gear);
    }

    neighbors.sort((a, b) => {
      const aCenterBias = Math.abs(a.center.x - GRID_CENTER.x) + Math.abs(a.center.y - GRID_CENTER.y);
      const bCenterBias = Math.abs(b.center.x - GRID_CENTER.x) + Math.abs(b.center.y - GRID_CENTER.y);
      return aCenterBias - bCenterBias;
    });
    return neighbors;
  }

  const root: DraftGear = {
    id: "hero-g0",
    teeth: WEAVE_TEETH,
    pitchRadius,
    outerRadius,
    center: cellCenter({ col: 0, row: 0 }),
    phaseTurn: 0,
    parity: 0,
    appearIndex: 0,
  };

  gears.push(root);
  gearByCell.set(cellKey({ col: 0, row: 0 }), root);
  contactAnglesByGearId.set(root.id, []);

  const cells = buildCells();
  for (const cell of cells) {
    if (gears.length >= targetCount) break;
    if (cell.col === 0 && cell.row === 0) continue;

    const center = cellCenter(cell);
    const placedNeighbors = getPlacedNeighbors(cell);
    if (placedNeighbors.length === 0) continue;

    const parent = placedNeighbors[0];
    const contactAngle = Math.atan2(center.y - parent.center.y, center.x - parent.center.x);
    const phaseTurn = solveNeighborPhaseTurn({
      currentTeeth: parent.teeth,
      neighborTeeth: WEAVE_TEETH,
      currentTurn: parent.phaseTurn ?? 0,
      contactAngleCurrentToNeighbor: contactAngle,
    });

    const candidate: DraftGear = {
      id: `hero-g${gears.length}`,
      teeth: WEAVE_TEETH,
      pitchRadius,
      outerRadius,
      center,
      phaseTurn,
      parity: (Math.abs(cell.col + cell.row) % 2 === 0 ? 0 : 1) as 0 | 1,
      parentId: parent.id,
      appearIndex: gears.length,
    };

    const verdict = evaluatePlacement(candidate, gears, contactAnglesByGearId, parent.id);
    if (!verdict.ok || verdict.neighbors.length === 0) continue;

    gears.push(candidate);
    gearByCell.set(cellKey(cell), candidate);
    registerContactAngles(candidate, verdict.neighbors);
  }

  return { gears, edges };
};
