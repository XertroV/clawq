import { pitchRadiusFromTeeth } from "../solver.ts";
import type { BackdropGeneratorFn, DraftGear, DraftMeshEdge } from "./types.ts";
import { generateBranchBackdrop } from "./branch.ts";
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

type ParentSlots = Map<string, Set<number>>;

export const generateLatticeBackdrop: BackdropGeneratorFn = ({ seed, targetCount = 64 }) => {
  const { random } = createGenerationContext(seed, 0x17a77);
  const gears: DraftGear[] = [];
  const edges: DraftMeshEdge[] = [];
  const contactAnglesByGearId = new Map<string, number[]>();
  const childCountByGearId = new Map<string, number>();
  const usedSlotsByGearId: ParentSlots = new Map();
  const edgeKeys = new Set<string>();

  function addEdge(a: string, b: string): void {
    const key = a < b ? `${a}|${b}` : `${b}|${a}`;
    if (!edgeKeys.has(key)) {
      edgeKeys.add(key);
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

  function markParentSlot(parentId: string, slot: number): void {
    if (!usedSlotsByGearId.has(parentId)) usedSlotsByGearId.set(parentId, new Set());
    usedSlotsByGearId.get(parentId)!.add(slot);
  }

  const rootTeeth = 20;
  const root: DraftGear = {
    id: "hero-g0",
    teeth: rootTeeth,
    pitchRadius: pitchRadiusFromTeeth(rootTeeth, HERO_GEAR_CIRCULAR_PITCH),
    outerRadius: outerRadiusFromTeeth(rootTeeth),
    center: { x: VIEWBOX.width * 0.5, y: 300 },
    phaseTurn: 0,
    parity: 0,
    appearIndex: 0,
  };
  gears.push(root);
  contactAnglesByGearId.set(root.id, []);
  childCountByGearId.set(root.id, 0);
  usedSlotsByGearId.set(root.id, new Set());

  const latticeBase = random() * Math.PI * 2;
  const maxAttempts = Math.max(12000, targetCount * 260);
  let attempts = 0;

  while (gears.length < targetCount && attempts < maxAttempts) {
    attempts += 1;
    const needLeftCoverage = !gears.some((gear) => gear.center.x + gear.outerRadius < -50);
    const needRightCoverage = !gears.some((gear) => gear.center.x - gear.outerRadius > VIEWBOX.width + 50);

    const candidateTeeth = random() < 0.8 ? randInt(random, 12, 18) : pickCandidateTeeth(random);
    const candidatePitch = pitchRadiusFromTeeth(candidateTeeth, HERO_GEAR_CIRCULAR_PITCH);

    const parentPool = gears
      .slice()
      .sort((a, b) => {
        const childDelta = (childCountByGearId.get(a.id) ?? 0) - (childCountByGearId.get(b.id) ?? 0);
        if (childDelta !== 0) return childDelta;
        const aEdgeBias = needLeftCoverage
          ? a.center.x
          : needRightCoverage
            ? VIEWBOX.width - a.center.x
            : Math.abs(a.center.x - VIEWBOX.width * 0.5);
        const bEdgeBias = needLeftCoverage
          ? b.center.x
          : needRightCoverage
            ? VIEWBOX.width - b.center.x
            : Math.abs(b.center.x - VIEWBOX.width * 0.5);
        return aEdgeBias - bEdgeBias;
      })
      .slice(0, Math.min(32, gears.length));
    if (parentPool.length === 0) continue;

    const parent = parentPool[randInt(random, 0, parentPool.length - 1)];
    const usedSlots = usedSlotsByGearId.get(parent.id) ?? new Set<number>();
    const freeSlots = [0, 1, 2, 3, 4, 5].filter((slot) => !usedSlots.has(slot));
    const slotChoices = freeSlots.length > 0 ? freeSlots : [0, 1, 2, 3, 4, 5];
    const slot = slotChoices[randInt(random, 0, slotChoices.length - 1)];

    const jitter = (random() - 0.5) * 0.11;
    const angle = latticeBase + (slot * Math.PI) / 3 + jitter;
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
    registerContactAngles(candidate, verdict.neighbors);
    markParentSlot(parent.id, slot);
    childCountByGearId.set(parent.id, (childCountByGearId.get(parent.id) ?? 0) + 1);
    childCountByGearId.set(candidate.id, 0);
    usedSlotsByGearId.set(candidate.id, new Set());
  }

  if (gears.length < Math.min(targetCount, 24)) {
    return generateBranchBackdrop({ seed: seed ^ 0x17a77, targetCount });
  }

  return { gears, edges };
};
