import { pitchRadiusFromTeeth } from "../solver.ts";
import type { BackdropGeneratorFn, DraftGear, DraftMeshEdge } from "./types.ts";
import {
  HERO_GEAR_CIRCULAR_PITCH,
  VIEWBOX,
  createGenerationContext,
  evaluatePlacement,
  outerRadiusFromTeeth,
  pickCandidateTeeth,
  pointAt,
  randInt,
  solveNeighborPhaseTurn,
} from "./shared.ts";

export const generateBranchBackdrop: BackdropGeneratorFn = ({ seed, targetCount = 90 }) => {
  const { random } = createGenerationContext(seed);
  const gears: DraftGear[] = [];
  const edges: DraftMeshEdge[] = [];
  const contactAnglesByGearId = new Map<string, number[]>();

  function addEdge(a: string, b: string): void {
    const key = a < b ? `${a}|${b}` : `${b}|${a}`;
    if (!edges.some((edge) => (edge.a < edge.b ? `${edge.a}|${edge.b}` : `${edge.b}|${edge.a}`) === key)) {
      edges.push({ a, b });
    }
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

  const rootTeeth = 22;
  const root: DraftGear = {
    id: "hero-g0",
    teeth: rootTeeth,
    pitchRadius: pitchRadiusFromTeeth(rootTeeth, HERO_GEAR_CIRCULAR_PITCH),
    outerRadius: outerRadiusFromTeeth(rootTeeth),
    center: { x: VIEWBOX.width * 0.5, y: 312 },
    phaseTurn: 0,
    parity: 0,
    appearIndex: 0,
  };
  gears.push(root);
  contactAnglesByGearId.set(root.id, []);

  let attempts = 0;
  while (gears.length < targetCount && attempts < 9000) {
    attempts += 1;
    const needLeftCoverage = !gears.some((gear) => gear.center.x + gear.outerRadius < -70);
    const needRightCoverage = !gears.some((gear) => gear.center.x - gear.outerRadius > VIEWBOX.width + 70);
    const directionMode: "left" | "right" | "mixed" = needLeftCoverage
      ? "left"
      : needRightCoverage
        ? "right"
        : random() < 0.33
          ? "left"
          : random() < 0.66
            ? "right"
            : "mixed";

    const candidateTeeth = pickCandidateTeeth(random);
    const candidatePitch = pitchRadiusFromTeeth(candidateTeeth, HERO_GEAR_CIRCULAR_PITCH);

    const parents = (directionMode === "mixed"
      ? gears.slice()
      : gears
          .slice()
          .sort((a, b) => (directionMode === "left" ? a.center.x - b.center.x : b.center.x - a.center.x)))
      .slice(0, directionMode === "mixed" ? Math.min(24, gears.length) : 12);
    const parent = parents[randInt(random, 0, parents.length - 1)];

    const spread = directionMode === "left" ? Math.PI : directionMode === "right" ? 0 : random() * Math.PI * 2;
    const angleChoices = [
      spread,
      spread + (random() - 0.5) * 0.8,
      spread + (random() - 0.5) * 1.4,
      spread + (random() - 0.5) * 2.0,
      spread + (random() - 0.5) * 2.6,
    ];

    const selectedAngle = angleChoices[randInt(random, 0, angleChoices.length - 1)];
    const center = pointAt(parent.center, selectedAngle, parent.pitchRadius + candidatePitch);
    const phaseTurn = solveNeighborPhaseTurn({
      currentTeeth: parent.teeth,
      neighborTeeth: candidateTeeth,
      currentTurn: parent.phaseTurn ?? 0,
      contactAngleCurrentToNeighbor: selectedAngle,
    });
    const newGear: DraftGear = {
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

    const verdict = evaluatePlacement(newGear, gears, contactAnglesByGearId, parent.id);
    if (!verdict.ok || verdict.neighbors.length > 1) continue;
    gears.push(newGear);
    registerContactAngles(newGear, verdict.neighbors);
  }

  return { gears, edges };
};
