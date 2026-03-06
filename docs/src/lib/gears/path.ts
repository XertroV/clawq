import type { Point, SolvedGear } from "./model";

export interface GearProfileTuning {
  valleyWidth: number;
  tipWidth: number;
  toothLength: number;
  roundness: number;
}

export const DEFAULT_GEAR_PROFILE_TUNING: GearProfileTuning = {
  valleyWidth: 0.07,
  tipWidth: 0.04,
  toothLength: 1,
  roundness: 3.5,
};

function polar(radius: number, angleRad: number): Point {
  return {
    x: Math.cos(angleRad) * radius,
    y: Math.sin(angleRad) * radius,
  };
}

function formatPoint(point: Point): string {
  return `${point.x.toFixed(3)} ${point.y.toFixed(3)}`;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function smootherstep(value: number): number {
  const t = clamp(value, 0, 1);
  return t * t * t * (t * (t * 6 - 15) + 10);
}

export function getTunedRadii(gear: SolvedGear, tuning: Partial<GearProfileTuning> = {}) {
  const resolved = { ...DEFAULT_GEAR_PROFILE_TUNING, ...tuning };
  const halfHeight = ((gear.outerRadius - gear.rootRadius) * 0.5) * resolved.toothLength;
  return {
    outerRadius: gear.pitchRadius + halfHeight,
    rootRadius: gear.pitchRadius - halfHeight,
  };
}

function toothRadiusAtOffset(
  gear: SolvedGear,
  normalizedOffset: number,
  tuning: Partial<GearProfileTuning> = {}
): number {
  const resolved = { ...DEFAULT_GEAR_PROFILE_TUNING, ...tuning };
  const { outerRadius, rootRadius } = getTunedRadii(gear, resolved);
  const phase = clamp(Math.abs(normalizedOffset) / 0.5, 0, 1);
  const tipWidth = clamp(resolved.tipWidth, 0, 0.45);
  const valleyWidth = clamp(resolved.valleyWidth, 0, 0.45);
  const valleyStart = clamp(1 - valleyWidth, tipWidth + 0.01, 1);

  let lift = 0;
  if (phase <= tipWidth) {
    lift = 1;
  } else if (phase >= valleyStart) {
    lift = 0;
  } else {
    const t = (phase - tipWidth) / (valleyStart - tipWidth);
    const baseLift = (Math.cos(t * Math.PI) + 1) * 0.5;

    const roundness = clamp(resolved.roundness, 0.2, 12);
    if (roundness >= 1) {
      const roundedT = smootherstep(t);
      const roundedLift = (Math.cos(roundedT * Math.PI) + 1) * 0.5;
      const roundMix = clamp((roundness - 1) / 11, 0, 1);
      lift = baseLift * (1 - roundMix) + roundedLift * roundMix;
    } else {
      const crispT = Math.pow(t, 0.72);
      const crispLift = (Math.cos(crispT * Math.PI) + 1) * 0.5;
      const crispMix = clamp((1 - roundness) / 0.8, 0, 1);
      lift = baseLift * (1 - crispMix) + crispLift * crispMix;
    }
  }

  return rootRadius + (outerRadius - rootRadius) * lift;
}

export function gearRadiusAtAngle(
  gear: SolvedGear,
  angleRad: number,
  tuning: Partial<GearProfileTuning> = {}
): number {
  const toothPitch = (Math.PI * 2) / gear.teeth;
  const toothPosition = angleRad / toothPitch;
  const fractional = toothPosition - Math.floor(toothPosition + 0.5);
  return toothRadiusAtOffset(gear, fractional, tuning);
}

export function sampleGearOutlinePoints(
  gear: SolvedGear,
  tuning: Partial<GearProfileTuning> = {}
): Point[] {
  const resolved = { ...DEFAULT_GEAR_PROFILE_TUNING, ...tuning };
  const points: Point[] = [];
  const samplesPerTooth = Math.round(clamp(34 + resolved.roundness * 10, 34, 140));
  const totalSamples = gear.teeth * samplesPerTooth;
  const startAngle = -Math.PI;

  for (let index = 0; index < totalSamples; index += 1) {
    const angle = startAngle + (index / totalSamples) * Math.PI * 2;
    const radius = gearRadiusAtAngle(gear, angle, tuning);
    points.push(polar(radius, angle));
  }

  return points;
}

export function buildGearPath(gear: SolvedGear, tuning: Partial<GearProfileTuning> = {}): string {
  const points = sampleGearOutlinePoints(gear, tuning);
  const commands = points.map((point, index) => `${index === 0 ? "M" : "L"} ${formatPoint(point)}`);
  commands.push("Z");
  return commands.join(" ");
}
