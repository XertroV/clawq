import { pitchRadiusFromTeeth } from "../solver.ts";
import type { DraftGear, DraftMeshEdge, Point } from "./types.ts";

export const HERO_GEAR_CIRCULAR_PITCH = 24;
export const VIEWBOX = { width: 1600, height: 760 };
export const MIN_TEETH = 12;
export const Y_MIN = -40;
export const Y_MAX = 500;
export const MESH_EPSILON = 0.2;
export const NON_MESH_CLEARANCE = 14;
export const TOOTH_LENGTH_FACTOR = 1.08;
export const CONTACT_ALIGNMENT_TOLERANCE = 0.03;
export const MESH_PHASE_OFFSET_TURNS = 0.5;
export const PHASE_CONSISTENCY_TOLERANCE = 0.03;

export type ContactAngleMap = Map<string, number[]>;

export type MeshedIntersectionCandidate = {
  center: Point;
  contactAngleFromA: number;
  contactAngleFromB: number;
};

export type GenerationContext = {
  seed: number;
  random: () => number;
};

export function createGenerationContext(seed: number, seedSalt = 0): GenerationContext {
  return {
    seed,
    random: mulberry32(seed ^ seedSalt),
  };
}

export function mulberry32(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state += 0x6d2b79f5;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function randInt(random: () => number, min: number, max: number): number {
  return Math.floor(random() * (max - min + 1)) + min;
}

export function pointAt(origin: Point, angleRad: number, distance: number): Point {
  return {
    x: origin.x + Math.cos(angleRad) * distance,
    y: origin.y + Math.sin(angleRad) * distance,
  };
}

export function dist(a: Point, b: Point): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

export function outerRadiusFromTeeth(teeth: number): number {
  const pitch = pitchRadiusFromTeeth(teeth, HERO_GEAR_CIRCULAR_PITCH);
  const gearModule = HERO_GEAR_CIRCULAR_PITCH / Math.PI;
  return pitch + gearModule * 0.82 * TOOTH_LENGTH_FACTOR;
}

export function pickCandidateTeeth(random: () => number): number {
  const roll = random();
  if (roll < 0.68) return randInt(random, 12, 18);
  if (roll < 0.9) return randInt(random, 19, 24);
  return randInt(random, 25, 28);
}

export function normalizeTurn(value: number): number {
  return ((value % 1) + 1) % 1;
}

export function meshEdgeKey(a: string, b: string): string {
  return a < b ? `${a}|${b}` : `${b}|${a}`;
}

function normalizeAngleDelta(angleRad: number): number {
  const tau = Math.PI * 2;
  return ((angleRad + Math.PI) % tau + tau) % tau - Math.PI;
}

export function ensureContactAngles(contactAnglesByGearId: ContactAngleMap, gearId: string): number[] {
  const existing = contactAnglesByGearId.get(gearId);
  if (existing) return existing;

  const created: number[] = [];
  contactAnglesByGearId.set(gearId, created);
  return created;
}

export function pushUniqueMeshEdge(edges: DraftMeshEdge[], a: string, b: string, edgeKeys?: Set<string>): void {
  const key = meshEdgeKey(a, b);
  if (edgeKeys) {
    if (edgeKeys.has(key)) return;
    edgeKeys.add(key);
    edges.push({ a, b });
    return;
  }

  if (!edges.some((edge) => meshEdgeKey(edge.a, edge.b) === key)) {
    edges.push({ a, b });
  }
}

export function registerMeshContacts(options: {
  gear: DraftGear;
  neighbors: DraftGear[];
  contactAnglesByGearId: ContactAngleMap;
  edges?: DraftMeshEdge[];
  edgeKeys?: Set<string>;
}): void {
  const { gear, neighbors, contactAnglesByGearId, edges, edgeKeys } = options;
  const gearContacts = ensureContactAngles(contactAnglesByGearId, gear.id);

  for (const neighbor of neighbors) {
    const angleFromGear = Math.atan2(neighbor.center.y - gear.center.y, neighbor.center.x - gear.center.x);
    if (!gearContacts.some((angle) => Math.abs(normalizeAngleDelta(angle - angleFromGear)) <= 1e-6)) {
      gearContacts.push(angleFromGear);
    }

    const neighborContacts = ensureContactAngles(contactAnglesByGearId, neighbor.id);
    const angleFromNeighbor = Math.atan2(gear.center.y - neighbor.center.y, gear.center.x - neighbor.center.x);
    if (!neighborContacts.some((angle) => Math.abs(normalizeAngleDelta(angle - angleFromNeighbor)) <= 1e-6)) {
      neighborContacts.push(angleFromNeighbor);
    }

    if (edges) pushUniqueMeshEdge(edges, gear.id, neighbor.id, edgeKeys);
  }
}

export function buildMeshedCandidateGear(options: {
  id: string;
  parent: DraftGear;
  teeth: number;
  angleRad: number;
  appearIndex: number;
  parentId?: string;
}): DraftGear {
  const { id, parent, teeth, angleRad, appearIndex, parentId = parent.id } = options;
  const pitchRadius = pitchRadiusFromTeeth(teeth, HERO_GEAR_CIRCULAR_PITCH);
  const center = pointAt(parent.center, angleRad, parent.pitchRadius + pitchRadius);

  return {
    id,
    teeth,
    pitchRadius,
    outerRadius: outerRadiusFromTeeth(teeth),
    center,
    phaseTurn: solveNeighborPhaseTurn({
      currentTeeth: parent.teeth,
      neighborTeeth: teeth,
      currentTurn: parent.phaseTurn ?? 0,
      contactAngleCurrentToNeighbor: angleRad,
    }),
    parity: parent.parity === 0 ? 1 : 0,
    parentId,
    appearIndex,
  };
}

export function getLegalContactSlots(options: {
  gear: DraftGear;
  slotCount: number;
  occupiedSlots?: Iterable<number>;
  angleOffsetRad?: number;
  candidateSlots?: number[];
  contactAnglesByGearId: ContactAngleMap;
}): number[] {
  const { gear, slotCount, occupiedSlots, angleOffsetRad = 0, candidateSlots, contactAnglesByGearId } = options;
  const occupied = occupiedSlots ? new Set(occupiedSlots) : new Set<number>();
  const slots = candidateSlots ?? Array.from({ length: slotCount }, (_, slot) => slot);
  const existingAngles = contactAnglesByGearId.get(gear.id) ?? [];

  return slots.filter((slot) => {
    if (occupied.has(slot)) return false;
    const angle = angleOffsetRad + (slot * Math.PI * 2) / slotCount;
    return isContactAngleCompatible(gear, existingAngles, angle);
  });
}

export function getTwoParentMeshedIntersections(options: {
  parentA: DraftGear;
  parentB: DraftGear;
  teeth: number;
}): MeshedIntersectionCandidate[] {
  const { parentA, parentB, teeth } = options;
  const candidatePitchRadius = pitchRadiusFromTeeth(teeth, HERO_GEAR_CIRCULAR_PITCH);
  const radiusA = parentA.pitchRadius + candidatePitchRadius;
  const radiusB = parentB.pitchRadius + candidatePitchRadius;
  const d = dist(parentA.center, parentB.center);

  if (d <= 1e-9) return [];
  if (d > radiusA + radiusB + MESH_EPSILON) return [];
  if (d < Math.abs(radiusA - radiusB) - MESH_EPSILON) return [];

  const a = (radiusA * radiusA - radiusB * radiusB + d * d) / (2 * d);
  const hSquared = radiusA * radiusA - a * a;
  if (hSquared < -MESH_EPSILON) return [];

  const h = Math.sqrt(Math.max(0, hSquared));
  const dx = (parentB.center.x - parentA.center.x) / d;
  const dy = (parentB.center.y - parentA.center.y) / d;
  const baseX = parentA.center.x + a * dx;
  const baseY = parentA.center.y + a * dy;
  const offsets = h <= MESH_EPSILON ? [0] : [-1, 1];

  return offsets.map((sign) => {
    const center = {
      x: baseX + sign * h * -dy,
      y: baseY + sign * h * dx,
    };

    return {
      center,
      contactAngleFromA: Math.atan2(center.y - parentA.center.y, center.x - parentA.center.x),
      contactAngleFromB: Math.atan2(center.y - parentB.center.y, center.x - parentB.center.x),
    };
  });
}

export function solveNeighborPhaseTurn(options: {
  currentTeeth: number;
  neighborTeeth: number;
  currentTurn: number;
  contactAngleCurrentToNeighbor: number;
}): number {
  // Be careful touching this: the sign convention here is easy to break and will make meshed gears visibly drift out of phase.
  const { currentTeeth, neighborTeeth, currentTurn, contactAngleCurrentToNeighbor } = options;
  const alphaA = contactAngleCurrentToNeighbor / (Math.PI * 2);
  const alphaB = (contactAngleCurrentToNeighbor + Math.PI) / (Math.PI * 2);

  return normalizeTurn(
    alphaB - (MESH_PHASE_OFFSET_TURNS - currentTeeth * (alphaA - currentTurn)) / neighborTeeth
  );
}

export function isContactAngleCompatible(gear: DraftGear, existingAngles: number[], newAngleRad: number): boolean {
  if (existingAngles.length === 0) return true;

  const pitch = (2 * Math.PI) / gear.teeth;
  const newTurns = newAngleRad / pitch;
  for (const angle of existingAngles) {
    const existingTurns = angle / pitch;
    const deltaTurns = normalizeTurn(newTurns - existingTurns);
    const nearest = Math.round(deltaTurns);
    const residual = Math.abs(deltaTurns - nearest);
    const wrappedResidual = Math.min(residual, Math.abs(1 - residual));
    if (wrappedResidual > CONTACT_ALIGNMENT_TOLERANCE) {
      return false;
    }
  }

  return true;
}

export function isPhaseTurnConsistentWithNeighbors(candidate: DraftGear, neighbors: DraftGear[]): boolean {
  if (candidate.phaseTurn == null) return true;

  for (const neighbor of neighbors) {
    if (neighbor.phaseTurn == null) continue;

    const expectedPhaseTurn = solveNeighborPhaseTurn({
      currentTeeth: neighbor.teeth,
      neighborTeeth: candidate.teeth,
      currentTurn: neighbor.phaseTurn,
      contactAngleCurrentToNeighbor: Math.atan2(
        candidate.center.y - neighbor.center.y,
        candidate.center.x - neighbor.center.x
      ),
    });
    const delta = normalizeTurn(candidate.phaseTurn - expectedPhaseTurn);
    const wrappedDelta = Math.min(delta, 1 - delta);
    if (wrappedDelta > PHASE_CONSISTENCY_TOLERANCE) return false;
  }

  return true;
}

export function evaluatePlacement(
  candidate: DraftGear,
  allGears: DraftGear[],
  contactAnglesByGearId: ContactAngleMap,
  requireParentId?: string,
  validatePhaseConsistency = false
): { ok: boolean; neighbors: DraftGear[] } {
  if (candidate.center.y < Y_MIN || candidate.center.y > Y_MAX) return { ok: false, neighbors: [] };
  if (candidate.center.x < -420 || candidate.center.x > VIEWBOX.width + 420) return { ok: false, neighbors: [] };

  const neighbors: DraftGear[] = [];

  for (const other of allGears) {
    const d = dist(candidate.center, other.center);
    const expected = candidate.pitchRadius + other.pitchRadius;
    const meshResidual = Math.abs(d - expected);
    const meshes = meshResidual <= MESH_EPSILON;

    if (meshes) {
      if (candidate.parity === other.parity) return { ok: false, neighbors: [] };

      const contactFromCandidate = Math.atan2(other.center.y - candidate.center.y, other.center.x - candidate.center.x);
      const existingCandidateContacts = neighbors.map((neighbor) =>
        Math.atan2(neighbor.center.y - candidate.center.y, neighbor.center.x - candidate.center.x)
      );
      if (!isContactAngleCompatible(candidate, existingCandidateContacts, contactFromCandidate)) {
        return { ok: false, neighbors: [] };
      }

      const contactFromOther = Math.atan2(candidate.center.y - other.center.y, candidate.center.x - other.center.x);
      const existingOtherContacts = contactAnglesByGearId.get(other.id) ?? [];
      if (!isContactAngleCompatible(other, existingOtherContacts, contactFromOther)) {
        return { ok: false, neighbors: [] };
      }

      neighbors.push(other);
      continue;
    }

    if (d < expected - MESH_EPSILON) return { ok: false, neighbors: [] };
    if (d < expected + NON_MESH_CLEARANCE) return { ok: false, neighbors: [] };
    if (d < candidate.outerRadius + other.outerRadius + 2) return { ok: false, neighbors: [] };
  }

  if (requireParentId && !neighbors.some((neighbor) => neighbor.id === requireParentId)) {
    return { ok: false, neighbors: [] };
  }

  if (validatePhaseConsistency && !isPhaseTurnConsistentWithNeighbors(candidate, neighbors)) {
    return { ok: false, neighbors: [] };
  }

  return { ok: true, neighbors };
}
