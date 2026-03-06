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
export type { GearProfileTuning } from "./path";
export type {
  GearProfileRange,
  GearProfileTuningRanges,
  GearTuningCandidate,
  GearTuningSearchOptions,
  GearTuningSearchResult,
} from "./tuning";
export { buildDebugOverlay } from "./debug";
export {
  buildGearPath,
  DEFAULT_GEAR_PROFILE_TUNING,
  gearRadiusAtAngle,
  getTunedRadii,
  sampleGearOutlinePoints,
} from "./path";
export {
  createMeshedPairScene,
  deriveToothCount,
  pitchRadiusFromTeeth,
  solveGearScene,
} from "./solver";
export {
  DEFAULT_GEAR_TUNING_RANGES,
  randomGearProfileTuning,
  solveGearProfileTuning,
} from "./tuning";
