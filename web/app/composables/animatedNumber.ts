import {computed, onBeforeUnmount, ref, watch, type ComputedRef} from "vue";

/** How long counting to a new value takes (ms). */
const DURATION = 600;

/**
 * The number of `source`, counting to each new value instead of jumping to it. The value it starts with is shown at
 * once, and so is every change if the user prefers reduced motion. Once there, it is exactly the new value.
 */
export function useAnimatedNumber(source: () => number): ComputedRef<number> {
  const value = ref(source());
  let frame: number | null = null;

  const stop = () => {
    if (frame !== null) {
      cancelAnimationFrame(frame);
      frame = null;
    }
  };

  watch(source, (target) => {
    stop();
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      value.value = target;
      return;
    }
    // from wherever it is, also when a change comes while counting
    const from = value.value;
    const start = performance.now();
    const step = (time: number) => {
      const progress = Math.min(1, Math.max(0, time - start) / DURATION);
      // ease-out cubic: fast at first, settling on the value
      value.value = progress < 1 ? from + (target - from) * (1 - (1 - progress) ** 3) : target;
      frame = progress < 1 ? requestAnimationFrame(step) : null;
    };
    frame = requestAnimationFrame(step);
  });

  onBeforeUnmount(stop);

  return computed(() => value.value);
}
