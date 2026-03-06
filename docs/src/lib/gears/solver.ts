import type {
  GearScene,
  GearSpec,
  MeshDiagnostic,
  Point,
  RotationDirection,
  SolvedGear,
  SolvedGearScene,
} from "./model";

interface DerivedGear {
  spec: GearSpec;
  center: Point;
  teeth: number;
  pitchRadius: number;
  module: number;
  outerRadius: number;
  rootRadius: number;
  holeRadius: number;
  innerRingRadius: number;
  angularVelocity: number;
  rotationDirection: RotationDirection;
  periodSec: number;
  phaseDeg: number;
}

function toDegrees(radians: number): number {
  return (radians * 180) / Math.PI;
}

function wrapHalfTurns(value: number): number {
  const shifted = ((value + 0.5) % 1 + 1) % 1;
  return shifted - 0.5;
}

function distance(a: Point, b: Point): number {
  return Math.hypot(b.x - a.x, b.y - a.y);
}

function pointAt(origin: Point, angleRad: number, length: number): Point {
  return {
    x: origin.x + Math.cos(angleRad) * length,
    y: origin.y + Math.sin(angleRad) * length,
  };
}

export function deriveToothCount(targetPitchRadius: number, circularPitch: number, minTeeth = 12): number {
  const raw = Math.round((2 * Math.PI * targetPitchRadius) / circularPitch);
  return Math.max(minTeeth, raw);
}

export function pitchRadiusFromTeeth(teeth: number, circularPitch: number): number {
  return (teeth * circularPitch) / (2 * Math.PI);
}

function deriveRenderableRadii(pitchRadius: number, circularPitch: number) {
  const gearModule = circularPitch / Math.PI;
  const outerRadius = pitchRadius + gearModule * 0.95;
  const rootRadius = Math.max(pitchRadius - gearModule * 1.15, pitchRadius * 0.66);
  return {
    module: gearModule,
    outerRadius,
    rootRadius,
    holeRadius: Math.max(pitchRadius * 0.16, gearModule * 1.8),
    innerRingRadius: pitchRadius * 0.48,
  };
}

export function createMeshedPairScene(config: {
  circularPitch: number;
  minTeeth?: number;
  driverId: string;
  driverPeriodSec: number;
  driverDirection: RotationDirection;
  first: { id: string; center: Point; targetPitchRadius: number };
  second: { id: string; idealCenter: Point; targetPitchRadius: number };
}): GearScene {
  const angleRad = Math.atan2(
    config.second.idealCenter.y - config.first.center.y,
    config.second.idealCenter.x - config.first.center.x
  );

  return {
    circularPitch: config.circularPitch,
    minTeeth: config.minTeeth,
    motion: {
      driverId: config.driverId,
      periodSec: config.driverPeriodSec,
      direction: config.driverDirection,
    },
    gears: [
      {
        id: config.first.id,
        center: config.first.center,
        targetPitchRadius: config.first.targetPitchRadius,
      },
      {
        id: config.second.id,
        placement: {
          kind: "mesh",
          with: config.first.id,
          angleRad,
        },
        targetPitchRadius: config.second.targetPitchRadius,
      },
    ],
  };
}

export function solveGearScene(scene: GearScene): SolvedGearScene {
  const minTeeth = scene.minTeeth ?? 12;
  const base = new Map<string, DerivedGear>();

  for (const gear of scene.gears) {
    if (gear.teeth === undefined && gear.targetPitchRadius === undefined) {
      throw new Error(`Gear '${gear.id}' must define either teeth or targetPitchRadius.`);
    }

    if (!gear.center && !gear.placement) {
      throw new Error(`Gear '${gear.id}' must define either a fixed center or a mesh placement.`);
    }

    const teeth = gear.teeth ?? deriveToothCount(gear.targetPitchRadius ?? 0, scene.circularPitch, minTeeth);
    if (teeth < minTeeth) {
      throw new Error(`Gear '${gear.id}' has too few teeth (${teeth}).`);
    }

    const pitchRadius = pitchRadiusFromTeeth(teeth, scene.circularPitch);
    const radii = deriveRenderableRadii(pitchRadius, scene.circularPitch);

    base.set(gear.id, {
      spec: gear,
      center: gear.center ?? { x: 0, y: 0 },
      teeth,
      pitchRadius,
      angularVelocity: 0,
      rotationDirection: scene.motion.direction,
      periodSec: scene.motion.periodSec,
      phaseDeg: 0,
      ...radii,
    });
  }

  const unresolved = new Set(scene.gears.filter((gear) => gear.placement).map((gear) => gear.id));
  let progress = true;
  while (unresolved.size > 0 && progress) {
    progress = false;

    for (const gearId of Array.from(unresolved)) {
      const gear = scene.gears.find((candidate) => candidate.id === gearId);
      if (!gear?.placement) {
        unresolved.delete(gearId);
        continue;
      }

      const current = base.get(gear.id);
      const parent = base.get(gear.placement.with);
      if (!current || !parent) {
        throw new Error(`Unable to place gear '${gear.id}' because its reference gear is missing.`);
      }

      if (!parent.spec.center && parent.spec.placement && unresolved.has(parent.spec.id)) {
        continue;
      }

      current.center = pointAt(parent.center, gear.placement.angleRad, parent.pitchRadius + current.pitchRadius);
      unresolved.delete(gearId);
      progress = true;
    }
  }

  if (unresolved.size > 0) {
    throw new Error(`Unable to resolve gear placements for: ${Array.from(unresolved).join(", ")}.`);
  }

  const driver = base.get(scene.motion.driverId);
  if (!driver) {
    throw new Error(`Driver gear '${scene.motion.driverId}' is missing.`);
  }

  const angularSpeed = (2 * Math.PI) / scene.motion.periodSec;
  driver.angularVelocity = scene.motion.direction === "cw" ? angularSpeed : -angularSpeed;
  driver.rotationDirection = scene.motion.direction;
  driver.periodSec = scene.motion.periodSec;

  const queue = [driver.spec.id];
  while (queue.length > 0) {
    const currentId = queue.shift();
    if (!currentId) {
      continue;
    }

    const current = base.get(currentId);
    if (!current) {
      continue;
    }

    for (const gear of scene.gears) {
      if (gear.placement?.with !== currentId) {
        continue;
      }

      const child = base.get(gear.id);
      if (!child) {
        continue;
      }

      child.angularVelocity = -current.angularVelocity * (current.teeth / child.teeth);
      child.rotationDirection = child.angularVelocity >= 0 ? "cw" : "ccw";
      child.periodSec = (2 * Math.PI) / Math.abs(child.angularVelocity);
      queue.push(child.spec.id);
    }
  }

  for (const gear of base.values()) {
    if (gear.spec.id === driver.spec.id) {
      continue;
    }

    if (gear.angularVelocity === 0) {
      throw new Error(`Gear '${gear.spec.id}' is not connected to driver '${driver.spec.id}'.`);
    }
  }

  const driverChildren = scene.gears.filter((gear) => gear.placement?.with === driver.spec.id);
  if (driverChildren.length > 0) {
    driver.phaseDeg = toDegrees(driverChildren[0].placement!.angleRad);
  }

  for (const gear of scene.gears) {
    if (!gear.placement) {
      continue;
    }

    const current = base.get(gear.id);
    if (!current) {
      continue;
    }

    const toothAngle = (2 * Math.PI) / current.teeth;
    const contactAngle = gear.placement.angleRad + Math.PI;
    current.phaseDeg = toDegrees(contactAngle - toothAngle * 0.5);
  }

  const diagnostics: MeshDiagnostic[] = [];
  for (const gear of scene.gears) {
    if (!gear.placement) {
      continue;
    }

    const current = base.get(gear.id);
    const parent = base.get(gear.placement.with);
    if (!current || !parent) {
      continue;
    }

    const expectedDistance = parent.pitchRadius + current.pitchRadius;
    const actualDistance = distance(parent.center, current.center);
    const pitchAngleParent = (2 * Math.PI) / parent.teeth;
    const pitchAngleCurrent = (2 * Math.PI) / current.teeth;
    const parentPhaseRad = (parent.phaseDeg * Math.PI) / 180;
    const currentPhaseRad = (current.phaseDeg * Math.PI) / 180;
    const phaseResidualA = wrapHalfTurns((gear.placement.angleRad - parentPhaseRad) / pitchAngleParent);
    const phaseResidualB = wrapHalfTurns((gear.placement.angleRad + Math.PI - currentPhaseRad) / pitchAngleCurrent - 0.5);

    diagnostics.push({
      a: parent.spec.id,
      b: current.spec.id,
      expectedDistance,
      actualDistance,
      distanceResidual: actualDistance - expectedDistance,
      phaseResidualA,
      phaseResidualB,
    });
  }

  const gears: SolvedGear[] = Array.from(base.values()).map((gear) => ({
    id: gear.spec.id,
    center: gear.center,
    teeth: gear.teeth,
    module: gear.module,
    circularPitch: scene.circularPitch,
    pitchRadius: gear.pitchRadius,
    outerRadius: gear.outerRadius,
    rootRadius: gear.rootRadius,
    holeRadius: gear.spec.render?.holeRadiusRatio
      ? gear.pitchRadius * gear.spec.render.holeRadiusRatio
      : gear.holeRadius,
    innerRingRadius: gear.spec.render?.innerRingRadiusRatio
      ? gear.pitchRadius * gear.spec.render.innerRingRadiusRatio
      : gear.innerRingRadius,
    angularVelocity: gear.angularVelocity,
    rotationDirection: gear.rotationDirection,
    periodSec: gear.periodSec,
    phaseDeg: gear.phaseDeg,
  }));

  return {
    circularPitch: scene.circularPitch,
    gears,
    diagnostics,
  };
}
