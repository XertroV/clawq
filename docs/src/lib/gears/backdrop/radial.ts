import { pitchRadiusFromTeeth } from "../solver.ts";
import type { BackdropGeneratorFn, DraftGear, DraftMeshEdge } from "./types.ts";
import {
  HERO_GEAR_CIRCULAR_PITCH,
  VIEWBOX,
  createGenerationContext,
  dist,
  evaluatePlacement,
  outerRadiusFromTeeth,
  pickCandidateTeeth,
  pointAt,
  randInt,
  solveNeighborPhaseTurn,
} from "./shared.ts";

const SPOKE_ANGLES = [0, Math.PI, Math.PI / 2, -Math.PI / 2, Math.PI / 3, -Math.PI / 3, (2 * Math.PI) / 3, (-2 * Math.PI) / 3];

type GrowthMode = "radial" | "left" | "right";

export const generateRadialBackdrop: BackdropGeneratorFn = ({ seed, targetCount = 80 }) => {
  const { random } = createGenerationContext(seed, 0x1f4a7d);
  const gears: DraftGear[] = [];
  const edges: DraftMeshEdge[] = [];
  const edgeKeySet = new Set<string>();
  const childCountByGearId = new Map<string, number>();
  const contactAnglesByGearId = new Map<string, number[]>();
  const radialOrigin = { x: VIEWBOX.width * 0.5, y: 300 };

  function addEdge(a: string, b: string): void {
    const key = a < b ? `${a}|${b}` : `${b}|${a}`;
    if (edgeKeySet.has(key)) return;
    edgeKeySet.add(key);
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

      childCountByGearId.set(neighbor.id, (childCountByGearId.get(neighbor.id) ?? 0) + 1);
      addEdge(gear.id, neighbor.id);
    }
  }

  function needsLeftCoverage(): boolean {
    return !gears.some((gear) => gear.center.x + gear.outerRadius < -70);
  }

  function needsRightCoverage(): boolean {
    return !gears.some((gear) => gear.center.x - gear.outerRadius > VIEWBOX.width + 70);
  }

  function pickGrowthMode(attempt: number): GrowthMode {
    const missingLeft = needsLeftCoverage();
    const missingRight = needsRightCoverage();

    if (missingLeft && missingRight) return attempt % 2 === 0 ? "left" : "right";
    if (missingLeft) return "left";
    if (missingRight) return "right";
    if (random() < 0.2) return "left";
    if (random() < 0.4) return "right";
    return "radial";
  }

  function pickParent(mode: GrowthMode): DraftGear {
    if (mode === "left" || mode === "right") {
      const sorted = gears
        .slice()
        .sort((a, b) => (mode === "left" ? a.center.x - b.center.x : b.center.x - a.center.x));
      const pool = sorted.slice(0, Math.min(16, sorted.length));
      return pool[randInt(random, 0, pool.length - 1)];
    }

    const frontier = gears
      .slice()
      .sort((a, b) => {
        const childDelta = (childCountByGearId.get(a.id) ?? 0) - (childCountByGearId.get(b.id) ?? 0);
        if (childDelta !== 0) return childDelta;
        return dist(radialOrigin, b.center) - dist(radialOrigin, a.center);
      });
    const pool = frontier.slice(0, Math.min(24, frontier.length));
    return pool[randInt(random, 0, pool.length - 1)];
  }

  function pickAngle(parent: DraftGear, mode: GrowthMode): number {
    if (mode === "left") return Math.PI + (random() - 0.5) * 0.55;
    if (mode === "right") return (random() - 0.5) * 0.55;

    const parentAngleFromOrigin = Math.atan2(parent.center.y - radialOrigin.y, parent.center.x - radialOrigin.x);
    const parentRadiusFromOrigin = dist(parent.center, radialOrigin);

    if (parentRadiusFromOrigin < 130 || random() < 0.3) {
      return SPOKE_ANGLES[randInt(random, 0, SPOKE_ANGLES.length - 1)] + (random() - 0.5) * 0.5;
    }

    let angle = parentAngleFromOrigin + (random() - 0.5) * 0.6;
    if (random() < 0.26) {
      angle += (random() < 0.5 ? -1 : 1) * (0.7 + random() * 0.8);
    }
    return angle;
  }

  function pickTeeth(mode: GrowthMode): number {
    if (mode !== "radial" && random() < 0.72) return randInt(random, 12, 16);
    return pickCandidateTeeth(random);
  }

  const rootTeeth = 24;
  const root: DraftGear = {
    id: "hero-g0",
    teeth: rootTeeth,
    pitchRadius: pitchRadiusFromTeeth(rootTeeth, HERO_GEAR_CIRCULAR_PITCH),
    outerRadius: outerRadiusFromTeeth(rootTeeth),
    center: radialOrigin,
    phaseTurn: 0,
    parity: 0,
    appearIndex: 0,
  };
  gears.push(root);
  childCountByGearId.set(root.id, 0);
  contactAnglesByGearId.set(root.id, []);

  let attempts = 0;
  while (gears.length < targetCount && attempts < 18000) {
    attempts += 1;

    const mode = pickGrowthMode(attempts);
    const parent = pickParent(mode);
    const candidateTeeth = pickTeeth(mode);
    const candidatePitch = pitchRadiusFromTeeth(candidateTeeth, HERO_GEAR_CIRCULAR_PITCH);
    const angle = pickAngle(parent, mode);
    const center = pointAt(parent.center, angle, parent.pitchRadius + candidatePitch);
    const contactAngle = Math.atan2(center.y - parent.center.y, center.x - parent.center.x);
    const phaseTurn = solveNeighborPhaseTurn({
      currentTeeth: parent.teeth,
      neighborTeeth: candidateTeeth,
      currentTurn: parent.phaseTurn ?? 0,
      contactAngleCurrentToNeighbor: contactAngle,
    });

    const candidate: DraftGear = {
      id: `hero-g${gears.length}`,
      teeth: candidateTeeth,
      pitchRadius: candidatePitch,
      outerRadius: outerRadiusFromTeeth(candidateTeeth),
      center,
      phaseTurn,
      parity: parent.parity === 0 ? 1 : 0,
      parentId: parent.id,
      appearIndex: gears.length,
    };

    const verdict = evaluatePlacement(candidate, gears, contactAnglesByGearId, parent.id);
    if (!verdict.ok || verdict.neighbors.length !== 1) continue;

    gears.push(candidate);
    childCountByGearId.set(candidate.id, 0);
    registerContactAngles(candidate, verdict.neighbors);
  }

  return { gears, edges };
};
