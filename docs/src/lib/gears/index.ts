export type {
  GearPlacement,
  GearRenderSpec,
  GearScene,
  GearSpec,
  MeshDiagnostic,
  Point,
  RotationDirection,
  SolvedGear,
  SolvedGearScene,
} from "./model";
export { buildDebugOverlay } from "./debug";
export { buildGearPath } from "./path";
export {
  createMeshedPairScene,
  deriveToothCount,
  pitchRadiusFromTeeth,
  solveGearScene,
} from "./solver";
