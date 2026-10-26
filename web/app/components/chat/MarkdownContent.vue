<template>
  <div class="markdown-content" v-html="html"></div>
</template>

<script lang="ts">
import {Marked} from "marked";
import DOMPurify from "dompurify";

// Module scope, so this runs once and not per message: DOMPurify hooks are global.
const markdown = new Marked({gfm: true});

// Links in answers point outside the app, so they open in a new tab.
DOMPurify.addHook('afterSanitizeAttributes', (node) => {
  if (node.tagName === 'A' && node.getAttribute('href')) {
    node.setAttribute('target', '_blank');
    node.setAttribute('rel', 'noopener noreferrer');
  }
});

function renderMarkdown(content: string): string {
  return DOMPurify.sanitize(markdown.parse(content, {async: false}));
}
</script>

<script setup lang="ts">
import {computed} from "vue";

const props = defineProps<{
  content: string,
}>();

const html = computed(() => renderMarkdown(props.content));
</script>

<style scoped>
.markdown-content {
  line-height: 1.6;
  overflow-wrap: anywhere;
}

.markdown-content :deep(> :first-child) {
  margin-top: 0;
}

.markdown-content :deep(> :last-child) {
  margin-bottom: 0;
}

.markdown-content :deep(p),
.markdown-content :deep(ul),
.markdown-content :deep(ol),
.markdown-content :deep(pre),
.markdown-content :deep(table),
.markdown-content :deep(blockquote) {
  margin: 0 0 12px 0;
}

.markdown-content :deep(h1),
.markdown-content :deep(h2),
.markdown-content :deep(h3),
.markdown-content :deep(h4),
.markdown-content :deep(h5),
.markdown-content :deep(h6) {
  margin: 20px 0 8px 0;
  line-height: 1.3;
  font-weight: 600;
}

.markdown-content :deep(h1) {
  font-size: 1.5rem;
}

.markdown-content :deep(h2) {
  font-size: 1.3rem;
}

.markdown-content :deep(h3) {
  font-size: 1.15rem;
}

.markdown-content :deep(h4),
.markdown-content :deep(h5),
.markdown-content :deep(h6) {
  font-size: 1rem;
}

.markdown-content :deep(ul),
.markdown-content :deep(ol) {
  padding-left: 24px;
}

.markdown-content :deep(li + li) {
  margin-top: 4px;
}

.markdown-content :deep(a) {
  color: rgb(var(--v-theme-primary));
}

.markdown-content :deep(code) {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 0.875em;
  background: rgba(var(--v-theme-on-surface), 0.06);
  border-radius: 4px;
  padding: 1px 5px;
}

.markdown-content :deep(pre) {
  background: #1e1e2e;
  color: #e6e6f0;
  /* sets it apart from a dark surface */
  border: thin solid rgba(var(--v-border-color), var(--v-border-opacity));
  border-radius: 8px;
  padding: 12px 16px;
  overflow-x: auto;
}

.markdown-content :deep(pre code) {
  background: none;
  color: inherit;
  padding: 0;
  font-size: 0.85rem;
  line-height: 1.5;
}

.markdown-content :deep(blockquote) {
  border-left: 4px solid rgba(var(--v-theme-on-surface), 0.15);
  padding-left: 12px;
  color: rgba(var(--v-theme-on-surface), 0.65);
}

.markdown-content :deep(table) {
  display: block;
  max-width: 100%;
  overflow-x: auto;
  border-collapse: collapse;
}

.markdown-content :deep(th),
.markdown-content :deep(td) {
  border: 1px solid rgba(var(--v-theme-on-surface), 0.12);
  padding: 6px 10px;
  text-align: left;
  /* Breaking words would squeeze the columns; the table scrolls instead. */
  overflow-wrap: normal;
}

.markdown-content :deep(th) {
  background: rgba(var(--v-theme-on-surface), 0.04);
  font-weight: 600;
}

.markdown-content :deep(hr) {
  border: none;
  border-top: 1px solid rgba(var(--v-theme-on-surface), 0.12);
  margin: 16px 0;
}

.markdown-content :deep(img) {
  max-width: 100%;
}
</style>
