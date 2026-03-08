export const BACKDROP_ALGORITHMS = [
  "branch",
  "chaos-bridged",
  "chaos-cavity",
  "chaos-cluster",
  "cell-fill",
  "chaos-fill",
  "constraint-solver",
  "hex-web",
  "lattice",
  "organic-field",
  "radial",
  "ring-web",
  "row-debug",
  "sine-debug",
  "topology-first",
  "weave",
] as const;

export const DEFAULT_HERO_GEAR_ALGORITHM = "organic-field" as const;

export type BackdropAlgorithm = (typeof BACKDROP_ALGORITHMS)[number];
