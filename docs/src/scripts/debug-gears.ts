import { createMeshedPairScene, solveGearScene } from '../lib/gears';
import { buildGearPath, getTunedRadii, sampleGearOutlinePoints } from '../lib/gears/path.ts';

type Point = { x: number; y: number };

type DebugConfig = {
  baseSceneConfig: {
    circularPitch: number;
    minTeeth: number;
    driverId: string;
    driverPeriodSec: number;
    driverDirection: 'cw' | 'ccw';
    first: { id: string; center: Point; targetPitchRadius: number };
    second: { id: string; idealCenter: Point; targetPitchRadius: number };
  };
  initialTuning: {
    valleyWidth: number;
    tipWidth: number;
    toothLength: number;
    roundness: number;
    rotationDeg: number;
    speed: number;
    showFullRotation: boolean;
    showGuides: boolean;
    showPolyline: boolean;
    showPhase: boolean;
  };
};

const ROOT_ID = 'gear-debug-root';
const MICRO_INTERSECTION_TOLERANCE = 2;

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

function transformPoint(point: Point, center: Point, rotationDeg: number): Point {
  const radians = (rotationDeg * Math.PI) / 180;
  const cosValue = Math.cos(radians);
  const sinValue = Math.sin(radians);
  return {
    x: center.x + point.x * cosValue - point.y * sinValue,
    y: center.y + point.x * sinValue + point.y * cosValue,
  };
}

function countIntersections(outlines: Point[][]): number {
  if (outlines.length < 2) return 0;
  let count = 0;

  for (let i = 0; i < outlines[0].length; i += 1) {
    const a1 = outlines[0][i];
    const a2 = outlines[0][(i + 1) % outlines[0].length];

    for (let j = 0; j < outlines[1].length; j += 1) {
      const b1 = outlines[1][j];
      const b2 = outlines[1][(j + 1) % outlines[1].length];
      if (segmentsIntersect(a1, a2, b1, b2)) count += 1;
    }
  }

  return count;
}

function formatValue(key: string, value: number): string {
  if (key === 'rotationDeg') return `${value.toFixed(1)} deg`;
  if (key === 'speed') return `${value.toFixed(2)}x`;
  return value.toFixed(3);
}

export function initGearDebug(): void {
  const root = document.getElementById(ROOT_ID);
  if (!root || root.dataset.gearDebugInit === '1') return;
  root.dataset.gearDebugInit = '1';

  const configElement = document.getElementById('gear-debug-config');
  if (!configElement?.textContent) return;
  const config = JSON.parse(configElement.textContent) as DebugConfig;

  const scene = solveGearScene(createMeshedPairScene(config.baseSceneConfig));
  const state = {
    ...config.initialTuning,
    isPlaying: false,
  };

  const controls = new Map(
    Array.from(root.querySelectorAll<HTMLInputElement>('[data-control]')).map((input) => [input.dataset.control ?? '', input])
  );
  controls.delete('');

  const outputs = new Map(
    Array.from(root.querySelectorAll<HTMLOutputElement>('[id^="value-"]')).map((output) => [output.id.replace('value-', ''), output])
  );

  const gearGroups = new Map(
    Array.from(root.querySelectorAll<SVGGElement>('[data-gear-group]')).map((element) => [element.dataset.gearGroup ?? '', element])
  );
  gearGroups.delete('');

  const isolatedGroups = new Map(
    Array.from(root.querySelectorAll<SVGGElement>('[data-isolated-gear]')).map((element) => [element.dataset.isolatedGear ?? '', element])
  );
  isolatedGroups.delete('');

  const overlapStatus = document.getElementById('overlap-status');
  const intersectionCount = document.getElementById('intersection-count');
  const driverRotationReadout = document.getElementById('driver-rotation-readout');
  const followerRotationReadout = document.getElementById('follower-rotation-readout');
  const playPauseButton = document.getElementById('play-pause');
  const resetButton = document.getElementById('reset-controls');
  const toggleFullRotation = document.getElementById('toggle-full-rotation') as HTMLInputElement | null;
  const toggleGuides = document.getElementById('toggle-guides') as HTMLInputElement | null;
  const togglePolyline = document.getElementById('toggle-polyline') as HTMLInputElement | null;
  const togglePhase = document.getElementById('toggle-phase') as HTMLInputElement | null;

  if (
    !overlapStatus ||
    !intersectionCount ||
    !driverRotationReadout ||
    !followerRotationReadout ||
    !playPauseButton ||
    !resetButton ||
    !toggleFullRotation ||
    !toggleGuides ||
    !togglePolyline ||
    !togglePhase
  ) {
    return;
  }

  const rootEl = root;
  const overlapStatusEl = overlapStatus;
  const intersectionCountEl = intersectionCount;
  const driverRotationReadoutEl = driverRotationReadout;
  const followerRotationReadoutEl = followerRotationReadout;
  const playPauseButtonEl = playPauseButton;
  const resetButtonEl = resetButton;
  const toggleFullRotationInput = toggleFullRotation;
  const toggleGuidesInput = toggleGuides;
  const togglePolylineInput = togglePolyline;
  const togglePhaseInput = togglePhase;

  function computeRotations(): Map<string, number> {
    const driver = scene.gears[0];
    const follower = scene.gears[1];
    const driverExtra = Number(state.rotationDeg);
    const followerExtra = -driverExtra * (driver.teeth / follower.teeth);

    return new Map([
      [driver.id, driver.phaseDeg + driverExtra],
      [follower.id, follower.phaseDeg + followerExtra],
    ]);
  }

  function updateStatus(intersections: number, rotations: Map<string, number>): void {
    const driver = scene.gears[0];
    const follower = scene.gears[1];
    const effectiveIntersections = intersections <= MICRO_INTERSECTION_TOLERANCE ? 0 : intersections;
    const clear = effectiveIntersections === 0;
    overlapStatusEl.textContent = clear ? 'Clear' : 'Overlap';
    overlapStatusEl.setAttribute('style', `color: ${clear ? 'var(--coq-teal-light)' : 'var(--error-red)'}`);
    intersectionCountEl.textContent = String(effectiveIntersections);
    driverRotationReadoutEl.textContent = `${(rotations.get(driver.id) ?? 0).toFixed(1)} deg`;
    followerRotationReadoutEl.textContent = `${(rotations.get(follower.id) ?? 0).toFixed(1)} deg`;
  }

  function render(): void {
    const tuning = {
      valleyWidth: Number(state.valleyWidth),
      tipWidth: Number(state.tipWidth),
      toothLength: Number(state.toothLength),
      roundness: Number(state.roundness),
    };

    const rotations = computeRotations();
    const transformedOutlines: Point[][] = [];

    for (const gear of scene.gears) {
      const tunedRadii = getTunedRadii(gear, tuning);
      const path = buildGearPath(gear, tuning);
      const points = sampleGearOutlinePoints(gear, tuning);
      const pointsString = points.map((point) => `${point.x.toFixed(2)},${point.y.toFixed(2)}`).join(' ');
      const rotation = rotations.get(gear.id) ?? 0;

      for (const group of [gearGroups.get(gear.id), isolatedGroups.get(gear.id)]) {
        if (!group) continue;
        if (group.dataset.gearGroup) {
          group.setAttribute('transform', `translate(${gear.center.x} ${gear.center.y}) rotate(${rotation})`);
        } else {
          group.setAttribute('transform', `rotate(${rotation})`);
        }

        const pathElement = group.querySelector<SVGPathElement>('[data-gear-path]');
        const pointsElement = group.querySelector<SVGPolylineElement>('[data-gear-points]');
        const outerGuide = group.querySelector<SVGCircleElement>('[data-guide="outer"]');
        const rootGuide = group.querySelector<SVGCircleElement>('[data-guide="root"]');
        const phaseMarker = group.querySelector<SVGLineElement>('[data-phase-marker]');

        pathElement?.setAttribute('d', path);
        pointsElement?.setAttribute('points', pointsString);
        outerGuide?.setAttribute('r', tunedRadii.outerRadius.toFixed(3));
        rootGuide?.setAttribute('r', tunedRadii.rootRadius.toFixed(3));
        if (phaseMarker) phaseMarker.style.display = state.showPhase ? '' : 'none';

        for (const guide of group.querySelectorAll<SVGElement>('[data-guide]')) {
          guide.style.display = state.showGuides ? '' : 'none';
        }

        if (pointsElement) pointsElement.style.display = state.showPolyline ? '' : 'none';
      }

      const outerMetric = rootEl.querySelector<HTMLElement>(`[data-metric="${gear.id}-outer"]`);
      const rootMetric = rootEl.querySelector<HTMLElement>(`[data-metric="${gear.id}-root"]`);
      const phaseMetric = rootEl.querySelector<HTMLElement>(`[data-metric="${gear.id}-phase"]`);
      if (outerMetric) outerMetric.textContent = tunedRadii.outerRadius.toFixed(2);
      if (rootMetric) rootMetric.textContent = tunedRadii.rootRadius.toFixed(2);
      if (phaseMetric) phaseMetric.textContent = `${rotation.toFixed(2)} deg`;

      transformedOutlines.push(points.map((point) => transformPoint(point, gear.center, rotation)));
    }

    updateStatus(countIntersections(transformedOutlines), rotations);
  }

  function syncOutputs(): void {
    for (const [key, input] of controls) {
      const value = Number(input.value);
      (state as Record<string, number | boolean | string>)[key] = value;
      const output = outputs.get(key);
      if (output) output.textContent = formatValue(key, value);
    }
  }

  function setRotationRange(): void {
    const rotationInput = controls.get('rotationDeg');
    if (!rotationInput) return;
    rotationInput.max = toggleFullRotationInput.checked ? '360' : '90';
    if (Number(rotationInput.value) > Number(rotationInput.max)) {
      rotationInput.value = rotationInput.max;
    }
    syncOutputs();
  }

  for (const input of controls.values()) {
    input.addEventListener('input', () => {
      syncOutputs();
      render();
    });
  }

  toggleFullRotationInput.addEventListener('change', () => {
    state.showFullRotation = toggleFullRotationInput.checked;
    setRotationRange();
    render();
  });

  toggleGuidesInput.addEventListener('change', () => {
    state.showGuides = toggleGuidesInput.checked;
    render();
  });

  togglePolylineInput.addEventListener('change', () => {
    state.showPolyline = togglePolylineInput.checked;
    render();
  });

  togglePhaseInput.addEventListener('change', () => {
    state.showPhase = togglePhaseInput.checked;
    render();
  });

  let animationFrame = 0;
  let lastTimestamp = 0;

  function tick(timestamp: number): void {
    if (!state.isPlaying) return;
    if (!lastTimestamp) lastTimestamp = timestamp;
    const deltaSec = (timestamp - lastTimestamp) / 1000;
    lastTimestamp = timestamp;

    const rotationInput = controls.get('rotationDeg');
    if (!rotationInput) return;
    const max = Number(rotationInput.max);
    const next = (Number(rotationInput.value) + deltaSec * 18 * Number(state.speed)) % max;
    rotationInput.value = next.toString();
    syncOutputs();
    render();
    animationFrame = requestAnimationFrame(tick);
  }

  playPauseButtonEl.addEventListener('click', () => {
    state.isPlaying = !state.isPlaying;
    playPauseButtonEl.textContent = state.isPlaying ? 'Pause' : 'Play';
    lastTimestamp = 0;

    if (state.isPlaying) {
      animationFrame = requestAnimationFrame(tick);
    } else {
      cancelAnimationFrame(animationFrame);
    }
  });

  resetButtonEl.addEventListener('click', () => {
    state.isPlaying = false;
    playPauseButtonEl.textContent = 'Play';
    cancelAnimationFrame(animationFrame);
    lastTimestamp = 0;

    for (const [key, input] of controls) {
      const resetValue = (config.initialTuning as Record<string, number | boolean>)[key];
      if (typeof resetValue === 'number') {
        input.value = String(resetValue);
      }
    }

    toggleFullRotationInput.checked = config.initialTuning.showFullRotation;
    toggleGuidesInput.checked = config.initialTuning.showGuides;
    togglePolylineInput.checked = config.initialTuning.showPolyline;
    togglePhaseInput.checked = config.initialTuning.showPhase;
    state.showFullRotation = config.initialTuning.showFullRotation;
    state.showGuides = config.initialTuning.showGuides;
    state.showPolyline = config.initialTuning.showPolyline;
    state.showPhase = config.initialTuning.showPhase;
    setRotationRange();
    syncOutputs();
    render();
  });

  setRotationRange();
  syncOutputs();
  render();
}
