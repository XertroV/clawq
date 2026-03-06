import type { Point, SolvedGear, SolvedGearScene } from "./model";
import { DEFAULT_GEAR_PROFILE_TUNING, type GearProfileTuning, sampleGearOutlinePoints } from "./path.ts";

export interface GearProfileRange {
  min: number;
  max: number;
}

export interface GearProfileTuningRanges {
  valleyWidth: GearProfileRange;
  tipWidth: GearProfileRange;
  toothLength: GearProfileRange;
  roundness: GearProfileRange;
}

export interface GearTuningCandidate {
  tuning: GearProfileTuning;
  intersections: number;
  containsOtherOutline: boolean;
  smoothnessPenalty: number;
  score: number;
}

export interface GearTuningSearchOptions {
  seed?: number;
  samples?: number;
  intersectionTolerance?: number;
  ranges?: Partial<GearProfileTuningRanges>;
  keepTop?: number;
}

export interface GearTuningSearchResult {
  best: GearTuningCandidate;
  top: GearTuningCandidate[];
}

export const DEFAULT_GEAR_TUNING_RANGES: GearProfileTuningRanges = {
  valleyWidth: { min: 0.02, max: 0.22 },
  tipWidth: { min: 0.01, max: 0.18 },
  toothLength: { min: 0.82, max: 1.28 },
  roundness: { min: 0.35, max: 6 },
};

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function mulberry32(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state += 0x6d2b79f5;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function randomInRange(random: () => number, range: GearProfileRange): number {
  return range.min + (range.max - range.min) * random();
}

function orient(p: Point, q: Point, r: Point): number {
  return (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x);
}

function segmentsIntersect(a1: Point, a2: Point, b1: Point, b2: Point): boolean {
  const o1 = orient(a1, a2, b1);
  const o2 = orient(a1, a2, b2);
  const o3 = orient(b1, b2, a1);
  const o4 = orient(b1, b2, a2);
  return Math.sign(o1) !== Math.sign(o2) && Math.sign(o3) !== Math.sign(o4);
}

function pointInPolygon(point: Point, polygon: Point[]): boolean {
  let inside = false;

  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i, i += 1) {
    const xi = polygon[i].x;
    const yi = polygon[i].y;
    const xj = polygon[j].x;
    const yj = polygon[j].y;
    const intersects =
      yi > point.y !== yj > point.y &&
      point.x < ((xj - xi) * (point.y - yi)) / (yj - yi) + xi;

    if (intersects) {
      inside = !inside;
    }
  }

  return inside;
}

function transformPoint(point: Point, center: Point, phaseDeg: number): Point {
  const phase = (phaseDeg * Math.PI) / 180;
  const cosPhase = Math.cos(phase);
  const sinPhase = Math.sin(phase);
  return {
    x: center.x + point.x * cosPhase - point.y * sinPhase,
    y: center.y + point.x * sinPhase + point.y * cosPhase,
  };
}

function countIntersections(a: Point[], b: Point[]): number {
  let intersections = 0;

  for (let i = 0; i < a.length; i += 1) {
    const a1 = a[i];
    const a2 = a[(i + 1) % a.length];

    for (let j = 0; j < b.length; j += 1) {
      const b1 = b[j];
      const b2 = b[(j + 1) % b.length];

      if (segmentsIntersect(a1, a2, b1, b2)) {
        intersections += 1;
      }
    }
  }

  return intersections;
}

function smoothnessPenalty(gear: SolvedGear, tuning: GearProfileTuning): number {
  const points = sampleGearOutlinePoints(gear, tuning);
  const radii = points.map((point) => Math.hypot(point.x, point.y));
  let penalty = 0;

  for (let i = 0; i < radii.length; i += 1) {
    const prev = radii[(i - 1 + radii.length) % radii.length];
    const current = radii[i];
    const next = radii[(i + 1) % radii.length];
    penalty += Math.abs(next - current * 2 + prev);
  }

  return penalty / radii.length;
}

function evaluatePair(gears: [SolvedGear, SolvedGear], tuning: GearProfileTuning): GearTuningCandidate {
  const [a, b] = gears;
  const outlineA = sampleGearOutlinePoints(a, tuning).map((point) => transformPoint(point, a.center, a.phaseDeg));
  const outlineB = sampleGearOutlinePoints(b, tuning).map((point) => transformPoint(point, b.center, b.phaseDeg));
  const intersections = countIntersections(outlineA, outlineB);
  const containsOtherOutline = pointInPolygon(outlineA[0], outlineB) || pointInPolygon(outlineB[0], outlineA);
  const smoothness = (smoothnessPenalty(a, tuning) + smoothnessPenalty(b, tuning)) * 0.5;

  const score = intersections * 120 + (containsOtherOutline ? 5000 : 0) + smoothness * 100 + Math.abs(tuning.toothLength - 1) * 6;

  return {
    tuning,
    intersections,
    containsOtherOutline,
    smoothnessPenalty: smoothness,
    score,
  };
}

function resolveRanges(overrides: Partial<GearProfileTuningRanges> = {}): GearProfileTuningRanges {
  return {
    valleyWidth: {
      min: overrides.valleyWidth?.min ?? DEFAULT_GEAR_TUNING_RANGES.valleyWidth.min,
      max: overrides.valleyWidth?.max ?? DEFAULT_GEAR_TUNING_RANGES.valleyWidth.max,
    },
    tipWidth: {
      min: overrides.tipWidth?.min ?? DEFAULT_GEAR_TUNING_RANGES.tipWidth.min,
      max: overrides.tipWidth?.max ?? DEFAULT_GEAR_TUNING_RANGES.tipWidth.max,
    },
    toothLength: {
      min: overrides.toothLength?.min ?? DEFAULT_GEAR_TUNING_RANGES.toothLength.min,
      max: overrides.toothLength?.max ?? DEFAULT_GEAR_TUNING_RANGES.toothLength.max,
    },
    roundness: {
      min: overrides.roundness?.min ?? DEFAULT_GEAR_TUNING_RANGES.roundness.min,
      max: overrides.roundness?.max ?? DEFAULT_GEAR_TUNING_RANGES.roundness.max,
    },
  };
}

export function randomGearProfileTuning(
  random: () => number = Math.random,
  ranges: Partial<GearProfileTuningRanges> = {}
): GearProfileTuning {
  const resolved = resolveRanges(ranges);
  return {
    valleyWidth: randomInRange(random, resolved.valleyWidth),
    tipWidth: randomInRange(random, resolved.tipWidth),
    toothLength: randomInRange(random, resolved.toothLength),
    roundness: randomInRange(random, resolved.roundness),
  };
}

export function solveGearProfileTuning(
  scene: SolvedGearScene,
  options: GearTuningSearchOptions = {}
): GearTuningSearchResult {
  const samples = Math.max(8, options.samples ?? 300);
  const tolerance = Math.max(0, options.intersectionTolerance ?? 2);
  const keepTop = clamp(options.keepTop ?? 5, 1, 20);
  const ranges = resolveRanges(options.ranges);

  if (scene.gears.length < 2) {
    const fallback = {
      tuning: DEFAULT_GEAR_PROFILE_TUNING,
      intersections: 0,
      containsOtherOutline: false,
      smoothnessPenalty: 0,
      score: 0,
    };
    return { best: fallback, top: [fallback] };
  }

  const random = mulberry32(options.seed ?? 0x1f2e3d4c);
  const pair = [scene.gears[0], scene.gears[1]] as [SolvedGear, SolvedGear];
  const candidates: GearTuningCandidate[] = [evaluatePair(pair, DEFAULT_GEAR_PROFILE_TUNING)];

  for (let i = 0; i < samples; i += 1) {
    const tuning = randomGearProfileTuning(random, ranges);
    candidates.push(evaluatePair(pair, tuning));
  }

  candidates.sort((a, b) => a.score - b.score);
  const viable = candidates.filter((candidate) =>
    candidate.intersections <= tolerance && !candidate.containsOtherOutline
  );

  if (viable.length > 0) {
    return {
      best: viable[0],
      top: viable.slice(0, keepTop),
    };
  }

  return {
    best: candidates[0],
    top: candidates.slice(0, keepTop),
  };
}
