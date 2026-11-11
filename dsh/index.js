// DeepSeek Harness entry for this Claude Code plugin. The plugin tree is read as is;
// the runtime is the published claude-plugin-dsh package, installed with `bun install` in dsh/.
import { createPlugin, rootFrom } from 'claude-plugin-dsh'

const plugin = createPlugin({ root: rootFrom(import.meta.url), commands: { prefix: 'wl', exclude: ['show'] } })
export const { name, apply } = plugin
export default plugin
