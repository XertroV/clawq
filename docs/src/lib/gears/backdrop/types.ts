export type Point = { x: number; y: number };

export type DraftGear = {
  id: string;
  teeth: number;
  pitchRadius: number;
  outerRadius: number;
  center: Point;
  phaseTurn?: number;
  parity: 0 | 1;
  parentId?: string;
  appearIndex: number;
};

export type DraftMeshEdge = {
  a: string;
  b: string;
};

export interface BackdropGeneratorOptions {
  seed: number;
  targetCount?: number;
  viewport?: {
    minX?: number;
    minY?: number;
    width: number;
    height: number;
  };
}

export type BackdropGeneratorResult = {
  gears: DraftGear[];
  edges: DraftMeshEdge[];
};

export type BackdropGeneratorFn = (options: BackdropGeneratorOptions) => BackdropGeneratorResult;
