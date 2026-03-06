import { pitchRadiusFromTeeth } from "../solver.ts";
import type { BackdropGeneratorFn, DraftGear, DraftMeshEdge } from "./types.ts";
import {
  HERO_GEAR_CIRCULAR_PITCH,
  VIEWBOX,
  createGenerationContext,
  outerRadiusFromTeeth,
  randInt,
  solveNeighborPhaseTurn,
} from "./shared.ts";

export const generateRowDebugBackdrop: BackdropGeneratorFn = ({ seed, targetCount = 999 }) => {
  const { random } = createGenerationContext(seed, 0x3301ab);
  const gears: DraftGear[] = [];
  const edges: DraftMeshEdge[] = [];
  const y = 282;
  let x = -620;
  let index = 0;
  let previous: DraftGear | null = null;
  const direction = 1;

  function pickDebugTeeth(): number {
    const roll = random();
    if (roll < 0.52) return randInt(random, 12, 14);
    if (roll < 0.88) return randInt(random, 15, 17);
    return randInt(random, 18, 20);
  }

  while (x < VIEWBOX.width + 620 && gears.length < targetCount) {
    const teeth = pickDebugTeeth();
    const pitchRadius = pitchRadiusFromTeeth(teeth, HERO_GEAR_CIRCULAR_PITCH);
    const outerRadius = outerRadiusFromTeeth(teeth);

    if (!previous) {
      const first: DraftGear = {
        id: `hero-g${index}`,
        teeth,
        pitchRadius,
        outerRadius,
        center: { x, y },
        phaseTurn: 0,
        parity: 0,
        appearIndex: index,
      };
      gears.push(first);
      previous = first;
      x += outerRadius + 14;
      index += 1;
      continue;
    }

    const centerX = previous.center.x + (previous.pitchRadius + pitchRadius) * direction;
    const centerY = previous.center.y;
    const contactAngle = Math.atan2(centerY - previous.center.y, centerX - previous.center.x);
    const phaseTurn = solveNeighborPhaseTurn({
      currentTeeth: previous.teeth,
      neighborTeeth: teeth,
      currentTurn: previous.phaseTurn ?? 0,
      contactAngleCurrentToNeighbor: contactAngle,
    });
    const gear: DraftGear = {
      id: `hero-g${index}`,
      teeth,
      pitchRadius,
      outerRadius,
      center: { x: centerX, y: centerY },
      phaseTurn,
      parity: previous.parity === 0 ? 1 : 0,
      parentId: previous.id,
      appearIndex: index,
    };
    gears.push(gear);
    edges.push({ a: previous.id, b: gear.id });
    previous = gear;
    x = centerX + outerRadius;
    index += 1;
  }

  return { gears, edges };
};
