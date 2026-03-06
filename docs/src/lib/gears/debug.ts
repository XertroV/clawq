import type { Point, SolvedGearScene } from "./model";

export interface DebugCircle {
  id: string;
  center: Point;
  radius: number;
  kind: "pitch" | "root" | "outer";
}

export interface DebugLine {
  id: string;
  from: Point;
  to: Point;
  residual: number;
}

export interface DebugOverlay {
  circles: DebugCircle[];
  lines: DebugLine[];
}

export function buildDebugOverlay(scene: SolvedGearScene): DebugOverlay {
  return {
    circles: scene.gears.flatMap((gear) => [
      { id: `${gear.id}-pitch`, center: gear.center, radius: gear.pitchRadius, kind: "pitch" as const },
      { id: `${gear.id}-root`, center: gear.center, radius: gear.rootRadius, kind: "root" as const },
      { id: `${gear.id}-outer`, center: gear.center, radius: gear.outerRadius, kind: "outer" as const },
    ]),
    lines: scene.diagnostics.map((diagnostic) => {
      const a = scene.gears.find((gear) => gear.id === diagnostic.a);
      const b = scene.gears.find((gear) => gear.id === diagnostic.b);
      return {
        id: `${diagnostic.a}-${diagnostic.b}`,
        from: a?.center ?? { x: 0, y: 0 },
        to: b?.center ?? { x: 0, y: 0 },
        residual: diagnostic.distanceResidual,
      };
    }),
  };
}
