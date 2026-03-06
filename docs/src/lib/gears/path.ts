import type { Point, SolvedGear } from "./model";

function polar(radius: number, angleRad: number): Point {
  return {
    x: Math.cos(angleRad) * radius,
    y: Math.sin(angleRad) * radius,
  };
}

function formatPoint(point: Point): string {
  return `${point.x.toFixed(3)} ${point.y.toFixed(3)}`;
}

export function buildGearPath(gear: SolvedGear): string {
  const toothPitch = (Math.PI * 2) / gear.teeth;
  const rootLead = toothPitch * 0.34;
  const tipHalf = toothPitch * 0.18;
  const firstStart = polar(gear.rootRadius, -toothPitch * 0.5);
  const commands: string[] = [`M ${formatPoint(firstStart)}`];

  for (let index = 0; index < gear.teeth; index += 1) {
    const center = index * toothPitch;
    const rootStart = center - rootLead;
    const tipStart = center - tipHalf;
    const tipEnd = center + tipHalf;
    const rootEnd = center + rootLead;

    const rootStartPoint = polar(gear.rootRadius, rootStart);
    const tipStartPoint = polar(gear.outerRadius, tipStart);
    const tipEndPoint = polar(gear.outerRadius, tipEnd);
    const rootEndPoint = polar(gear.rootRadius, rootEnd);

    commands.push(`A ${gear.rootRadius.toFixed(3)} ${gear.rootRadius.toFixed(3)} 0 0 1 ${formatPoint(rootStartPoint)}`);
    commands.push(`L ${formatPoint(tipStartPoint)}`);
    commands.push(`A ${gear.outerRadius.toFixed(3)} ${gear.outerRadius.toFixed(3)} 0 0 1 ${formatPoint(tipEndPoint)}`);
    commands.push(`L ${formatPoint(rootEndPoint)}`);
  }

  commands.push("Z");
  return commands.join(" ");
}
