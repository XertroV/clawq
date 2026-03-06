export interface Point {
  x: number;
  y: number;
}

export type RotationDirection = "cw" | "ccw";

export interface GearPlacement {
  kind: "mesh";
  with: string;
  angleRad: number;
}

export interface GearRenderSpec {
  holeRadiusRatio?: number;
  innerRingRadiusRatio?: number;
}

export interface GearSpec {
  id: string;
  center?: Point;
  placement?: GearPlacement;
  targetPitchRadius?: number;
  teeth?: number;
  render?: GearRenderSpec;
}

export interface GearMotionSpec {
  driverId: string;
  periodSec: number;
  direction: RotationDirection;
}

export interface GearScene {
  circularPitch: number;
  minTeeth?: number;
  gears: GearSpec[];
  motion: GearMotionSpec;
}

export interface MeshDiagnostic {
  a: string;
  b: string;
  expectedDistance: number;
  actualDistance: number;
  distanceResidual: number;
  phaseResidualA: number;
  phaseResidualB: number;
}

export interface SolvedGear {
  id: string;
  center: Point;
  teeth: number;
  module: number;
  circularPitch: number;
  pitchRadius: number;
  outerRadius: number;
  rootRadius: number;
  holeRadius: number;
  innerRingRadius: number;
  angularVelocity: number;
  rotationDirection: RotationDirection;
  periodSec: number;
  phaseDeg: number;
}

export interface SolvedGearScene {
  circularPitch: number;
  gears: SolvedGear[];
  diagnostics: MeshDiagnostic[];
}
