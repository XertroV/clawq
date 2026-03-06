import { pitchRadiusFromTeeth } from "../solver.ts";
import type { BackdropGeneratorFn, DraftGear, DraftMeshEdge } from "./types.ts";
import { HERO_GEAR_CIRCULAR_PITCH, VIEWBOX, createGenerationContext, outerRadiusFromTeeth, solveNeighborPhaseTurn } from "./shared.ts";

export const generateSineDebugBackdrop: BackdropGeneratorFn = ({ seed, targetCount = 999 }) => {
  const { random } = createGenerationContext(seed, 0x53a91d);
  const gears: DraftGear[] = [];
  const edges: DraftMeshEdge[] = [];
  const baseY = 282;
  const amplitude = 56 + random() * 18;
  const wavelength = 280 + random() * 120;
  const phaseOffset = random() * Math.PI * 2;
  const fixedTeeth = 12;
  const pitchRadius = pitchRadiusFromTeeth(fixedTeeth, HERO_GEAR_CIRCULAR_PITCH);
  const outerRadius = outerRadiusFromTeeth(fixedTeeth);
  const meshDistance = pitchRadius * 2;
  let x = -500;
  let index = 0;
  let previous: DraftGear | null = null;

  function yAt(centerX: number): number {
    return baseY + Math.sin(centerX / wavelength + phaseOffset) * amplitude;
  }

  while (x < VIEWBOX.width + 500 && gears.length < targetCount) {
    if (!previous) {
      const first: DraftGear = {
        id: `hero-g${index}`,
        teeth: fixedTeeth,
        pitchRadius,
        outerRadius,
        center: { x, y: yAt(x) },
        phaseTurn: 0,
        parity: 0,
        appearIndex: index,
      };
      gears.push(first);
      previous = first;
      x += outerRadius;
      index += 1;
      continue;
    }

    let centerX = previous.center.x + meshDistance;
    let centerY = yAt(centerX);
    let attempts = 0;

    while (attempts < 12) {
      const dy = centerY - previous.center.y;
      const remaining = meshDistance * meshDistance - dy * dy;
      if (remaining > 1e-6) {
        centerX = previous.center.x + Math.sqrt(remaining);
        centerY = yAt(centerX);
      }
      attempts += 1;
    }

    const contactAngle = Math.atan2(centerY - previous.center.y, centerX - previous.center.x);
    const phaseTurn = solveNeighborPhaseTurn({
      currentTeeth: previous.teeth,
      neighborTeeth: fixedTeeth,
      currentTurn: previous.phaseTurn ?? 0,
      contactAngleCurrentToNeighbor: contactAngle,
    });

    const gear: DraftGear = {
      id: `hero-g${index}`,
      teeth: fixedTeeth,
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
