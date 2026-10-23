import {computed, onBeforeUnmount, ref, watch, type ComputedRef} from "vue";

export interface SmoothText {
  text: ComputedRef<string>,
  /** Whether part of the text is not shown yet. */
  revealing: ComputedRef<boolean>,
}

/** Characters per second at least, so the rest of a batch does not trail off. */
const MIN_SPEED = 120;
/** The text not shown yet is revealed at a rate that would show it within this long (ms), so it keeps up with the stream. */
const CATCH_UP_MS = 250;

/**
 * The text of `source`, revealing what is appended to it gradually instead of in the batches it arrives in.
 * The text it starts with, and any change other than an append, is shown at once.
 */
export function useSmoothText(source: () => string): SmoothText {
  const target = ref(source());
  const shown = ref(target.value.length);
  /** Fractional, `shown` is its floor. */
  let position = shown.value;
  let frame: number | null = null;
  let last = 0;

  const stop = () => {
    if (frame !== null) {
      cancelAnimationFrame(frame);
      frame = null;
    }
  };

  const step = (time: number) => {
    const elapsed = Math.max(0, time - last);
    last = time;
    const length = target.value.length;
    const speed = Math.max(MIN_SPEED / 1000, (length - position) / CATCH_UP_MS);
    position = Math.min(length, position + speed * elapsed);
    shown.value = Math.floor(position);
    frame = position < length ? requestAnimationFrame(step) : null;
  };

  watch(source, (text) => {
    const appended = text.startsWith(target.value.slice(0, shown.value));
    target.value = text;
    if (!appended || window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      stop();
      position = text.length;
      shown.value = position;
    } else if (frame === null && shown.value < text.length) {
      last = performance.now();
      frame = requestAnimationFrame(step);
    }
  });

  onBeforeUnmount(stop);

  const text = computed(() => {
    let end = shown.value;
    // not between the halves of a surrogate pair
    const code = target.value.charCodeAt(end - 1);
    if (code >= 0xd800 && code <= 0xdbff) {
      end++;
    }
    return target.value.slice(0, end);
  });

  return {text, revealing: computed(() => text.value.length < target.value.length)};
}
