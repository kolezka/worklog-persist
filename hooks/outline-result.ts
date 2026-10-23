import type { EngineInterface, McpToolResult } from 'claude-code'

import { DecodeError } from './worklog-panel'

type ReadTool = 'list_collections' | 'list_collection_documents' | 'fetch'
const FILE_LIMIT = 4 * 1024 * 1024
const SAVED_NOTICE = /^Error: result \([\d,]+ characters\) exceeds maximum allowed tokens\. Output has been saved to (\/[^\n]+\.txt)\.(?:\n|$)/

/** Large native MCP calls return a host notice; the original blocks stay in a session file. */
export async function readOutline(
  $: Pick<EngineInterface, 'mcp' | 'env' | 'session' | 'fs'>,
  server: string,
  tool: ReadTool,
  args: Record<string, unknown>,
): Promise<McpToolResult> {
  const result = await $.mcp.call(server, tool, args)
  if (result.isError || result.content.length !== 1) return result
  const block = result.content[0]
  const path = block?.type === 'text' && typeof block.text === 'string'
    ? SAVED_NOTICE.exec(block.text)?.[1]
    : undefined
  if (!path) return result

  const configured = await $.env.get('CLAUDE_CONFIG_DIR')
  const home = await $.env.get('HOME')
  const config = configured || (home ? `${home}/.claude` : undefined)
  if (!config?.startsWith('/')) throw new DecodeError('cannot locate the session result directory')
  const root = `${config.replace(/\/+$/, '')}/projects`
  const sessionId = await $.session.id()
  const parts = path.startsWith(`${root}/`) ? path.slice(root.length + 1).split('/') : []
  const name = parts[3] ?? ''
  const prefix = `mcp-${server}-${tool}-`
  if (
    parts.length !== 4 || !parts[0] || parts[1] !== sessionId || parts[2] !== 'tool-results' ||
    path.includes('\\') || path.split('/').some(part => part === '.' || part === '..') ||
    !name.startsWith(prefix) || !/^\d+\.txt$/.test(name.slice(prefix.length))
  ) {
    throw new DecodeError('saved Outline result is outside this session or belongs to another tool')
  }

  const directory = await $.fs.stat(root, { resolve: true })
  const file = await $.fs.stat(path, { resolve: true })
  const expected = directory.realPath ? `${directory.realPath.replace(/\/+$/, '')}/${parts.join('/')}` : null
  if (directory.kind !== 'dir' || file.kind !== 'file' || file.isLink || !expected || file.realPath !== expected) {
    throw new DecodeError('saved Outline result does not resolve inside this session result directory')
  }
  if (file.size > FILE_LIMIT) throw new DecodeError('saved Outline result exceeds the native 4 MiB file-read limit')

  const raw = await $.fs.read(file.realPath)
  let content: unknown
  try {
    content = JSON.parse(raw)
  } catch {
    throw new DecodeError('saved Outline result is not JSON')
  }
  if (!Array.isArray(content) || !content.every(item =>
    typeof item === 'object' && item !== null && item.type === 'text' && typeof item.text === 'string',
  )) {
    throw new DecodeError('saved Outline result is not an array of text content blocks')
  }
  return { ...result, content }
}
