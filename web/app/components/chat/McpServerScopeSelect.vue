<template>
  <ScopeSelect :model-value="scope" :items="items" :header="$t('mcpServers.title')"
               :all-title="$t('chat.allMcpServers')" icon="mdi-puzzle-outline" none-icon="mdi-puzzle-remove-outline"
               :title="mcpServerScopeSummary(props.modelValue, props.servers)" :disabled="props.disabled"
               @update:model-value="emit('update:modelValue', {all_mcp_servers: $event.all, mcp_server_ids: $event.ids})"/>
</template>

<script setup lang="ts">
import {computed} from "vue";
import {type McpServerDto, type McpServerScope, McpServerStatus} from "~/utils/model";
import {enabledMcpToolCount, mcpServerScopeSummary, mcpServerStatusLabel, mcpToolCountLabel} from "~/utils/utils";
import ScopeSelect, {type Scope, type ScopeItem} from "~/components/chat/ScopeSelect.vue";

const props = defineProps<{
  modelValue: McpServerScope,
  /** The servers that can be selected, see `isMcpServerOn`. */
  servers: McpServerDto[],
  disabled?: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: McpServerScope): void,
}>();

const scope = computed<Scope>(() => ({all: props.modelValue.all_mcp_servers, ids: props.modelValue.mcp_server_ids}));

const items = computed<ScopeItem[]>(() => props.servers.map(s => ({id: s.id, title: s.name, subtitle: problem(s)})));

/**
 * Why the model doesn't get the server's tools for now, `undefined` if it does. The servers are on, so this is
 * `!isMcpServerUsed` in words.
 */
const problem = (server: McpServerDto): string | undefined => {
  if (server.status !== McpServerStatus.READY) {
    return mcpServerStatusLabel(server.status);
  }
  return enabledMcpToolCount(server) === 0 ? mcpToolCountLabel(server) : undefined;
};
</script>
