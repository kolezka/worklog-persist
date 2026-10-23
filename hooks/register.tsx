// Native worklog panel: a Mods pane for the current project's worklog.
// Reads Outline read-only through the session's connected MCP server and runs
// lifecycle actions through the plugin's own slash commands. It never writes
// to Outline itself. Helpers and decoders live in ./worklog-panel.ts.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { WorklogPanel, WorklogVerb } from '../types'
import { readOutline } from './outline-result'
import {
  DecodeError,
  LIST_PAGE,
  LOAD_LIMIT,
  PAGE_CHARS,
  SLUG_RE,
  TASK_VERBS,
  VERBS,
  decodeCollections,
  decodeFetch,
  decodeTree,
  frameForSession,
  pageCount,
  parseIdentity,
  pickOutline,
  resolveScope,
  section,
} from './worklog-panel'

const PANE = 'worklog-panel'
const TITLE = 'Worklog'
const PHRASE = 'show worklog panel'
const SHOW_COMMAND = 'worklog-persist:show'

const EMPTY: WorklogPanel = {
  cwd: null,
  token: '',
  phase: 'idle',
  message: null,
  isFailure: false,
  identity: null,
  persistence: 'unknown',
  toolPrefix: null,
  projectId: null,
  docs: [],
  activeTask: null,
  taskDetail: null,
  commands: [],
  query: '',
  taskPage: 0,
  docPage: 0,
  preview: null,
  loadNote: null,
  action: null,
  isDirty: false,
  held: null,
}

// Change the tag when WorklogPanel changes: a reload then declines older values.
const panel = atom({ plugin: 'worklog-persist', key: 'panel' } as const, EMPTY, { shape: 'panel-2' })

type $ = EngineInterface

const newToken = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`
const errorText = (e: unknown) =>
  e instanceof DecodeError ? e.message : e instanceof Error ? e.message : String(e)

async function script($: $, cwd: string, name: string, args: string[] = []) {
  return $.process.run(['/bin/bash', `${$.plugin.root}/scripts/${name}`, ...args], { cwd })
}

async function listCommands($: $): Promise<WorklogPanel['commands']> {
  const all = await $.command.list()
  const out: WorklogPanel['commands'] = []
  for (const verb of VERBS) {
    const hit =
      all.find(c => c.name === `worklog-persist:${verb}`) ??
      all.find(c => c.name === verb && c.plugin === 'worklog-persist')
    if (hit) out.push({ verb, command: hit.name })
  }
  return out
}

/** Re-reads identity and the project tree. A newer refresh makes this one's answers void. */
async function refresh($: $): Promise<void> {
  const token = newToken()
  const cwd = await $.session.cwd()
  await updatePanel($, (p): WorklogPanel => {
    const kept = p.cwd === cwd ? p : EMPTY
    const kbPath = kept.identity?.kbPath
    // Nothing of the old snapshot is shown or usable until this refresh confirms the scope.
    const held =
      kept.phase === 'ready' && kept.projectId && kbPath
        ? { kbPath, activeTask: kept.activeTask, previewId: kept.preview?.id ?? null }
        : kept.held
    return {
      ...kept,
      cwd,
      token,
      phase: 'loading',
      message: null,
      isFailure: false,
      isDirty: false,
      identity: null,
      persistence: 'unknown',
      projectId: null,
      docs: [],
      activeTask: null,
      taskDetail: null,
      preview: null,
      loadNote: null,
      action: kept.action?.phase === 'editing' ? null : kept.action,
      held,
    }
  })
  const commit = (fn: (p: WorklogPanel) => WorklogPanel) =>
    updatePanel($, p => (p.token === token ? fn(p) : p))
  const stop = (message: string, isFailure: boolean) =>
    commit(p => ({ ...p, phase: isFailure ? 'error' : 'ready', message, isFailure, docs: [], projectId: null }))

  try {
    const commands = await listCommands($)
    const resolved = await script($, cwd, 'resolve-context.sh')
    if (resolved.exitCode !== 0) {
      return void (await stop(`resolve-context.sh exited ${resolved.exitCode}: ${resolved.stderr.trim()}`, true))
    }
    const identity = parseIdentity(resolved.stdout)
    const state = await script($, cwd, 'persistence-state.sh', ['status'])
    const word = state.stdout.trim()
    const persistence = word === 'on' || word === 'off' ? word : 'unknown'
    await commit(p => ({ ...p, identity, persistence, commands }))

    const configError = identity.configError
    if (configError && !configError.startsWith('config not found')) {
      return void (await stop(`${configError}. Fix the config file, then refresh.`, true))
    }
    if (identity.ignored) {
      return void (await stop('This repo is ignored: it is not persisted to Outline.', false))
    }
    if (identity.world === 'UNRESOLVED' || !identity.kbPath) {
      return void (await stop('This repo is not set up for Outline yet. Run setup.', false))
    }

    const outline = pickOutline(await $.tool.list())
    if (!outline) return void (await stop('The Outline MCP server is not connected in this session.', true))
    await commit(p => ({ ...p, toolPrefix: outline.prefix }))

    const rootName = identity.kbPath.split('/')[0] ?? ''
    const roots = []
    for (let offset = 0; ; offset += 100) {
      const page = decodeCollections(await readOutline($, outline.server, 'list_collections', { limit: 100, offset }))
      roots.push(...page.filter(c => c.name === rootName))
      if (page.length < 100) break
    }
    if (roots.length > 1) throw new DecodeError(`two collections are named "${rootName}"`)
    const root = roots[0]
    if (!root) {
      return void (await stop(`Not found in Outline: the collection ${rootName} is missing. This panel creates nothing; the lifecycle commands create it or ask which collection to use.`, false))
    }
    const tree = decodeTree(await readOutline($, outline.server, 'list_collection_documents', { collectionId: root.id }))
    const scope = resolveScope(tree, identity.kbPath)
    if (scope.kind === 'missing') {
      return void (await stop(`Not found in Outline: ${scope.path} is missing. The first write creates it; this panel creates nothing.`, false))
    }
    const ids = new Set(scope.docs.map(d => d.id))
    let previewId: string | null = null
    await commit(p => {
      const same = p.held?.kbPath === identity.kbPath ? p.held : null
      previewId = same?.previewId && ids.has(same.previewId) ? same.previewId : null
      return {
        ...p,
        phase: 'ready',
        message: null,
        projectId: scope.project.id,
        docs: scope.docs,
        activeTask: same?.activeTask && ids.has(same.activeTask.id) ? same.activeTask : null,
        held: null,
      }
    })
    const now = await read($, panel)
    if (now.token !== token) return
    if (now.activeTask) await loadTask($, now.activeTask.id)
    if (previewId) await showPreview($, previewId)
  } catch (e) {
    await stop(`Could not read Outline: ${errorText(e)}`, true)
  }
}

async function fetchInScope($: $, id: string) {
  const p = await read($, panel)
  if (p.phase !== 'ready') throw new DecodeError('the project scope is not confirmed yet')
  const doc = p.docs.find(d => d.id === id)
  if (!doc) throw new DecodeError('that document is outside the current project')
  const outline = pickOutline(await $.tool.list())
  if (!outline) throw new DecodeError('the Outline MCP server is not connected')
  const got = decodeFetch(await readOutline($, outline.server, 'fetch', { resource: 'document', id }))
  if (got.id !== id || got.parentId !== doc.parentId) {
    throw new DecodeError('Outline answered with a document that is not the requested one, or sits outside the project')
  }
  return { doc, got }
}

async function chooseTask($: $, id: string, slug: string) {
  const p = await read($, panel)
  if (p.phase !== 'ready' || !p.docs.some(d => d.id === id && d.kind === 'task')) return
  const scope = p.token
  await updatePanel($, q => (q.token === scope ? { ...q, activeTask: { id, slug }, loadNote: null } : q))
  await loadTask($, id)
}

async function loadTask($: $, id: string) {
  const token = newToken()
  const scope = (await read($, panel)).token
  await updatePanel($, (p): WorklogPanel =>
    p.token === scope
      ? { ...p, taskDetail: { id, token, phase: 'loading', status: null, nextAction: null, message: null } }
      : p,
  )
  // A read that lands after another refresh, or another task, is dropped.
  const commit = (fn: (d: NonNullable<WorklogPanel['taskDetail']>) => WorklogPanel['taskDetail']) =>
    updatePanel($, p =>
      p.token === scope && p.taskDetail?.token === token && p.activeTask?.id === id ? { ...p, taskDetail: fn(p.taskDetail) } : p,
    )
  try {
    const { got } = await fetchInScope($, id)
    await commit(d => ({ ...d, phase: 'ready', status: section(got.text, 'Status'), nextAction: section(got.text, 'Next action') }))
  } catch (e) {
    await commit(d => ({ ...d, phase: 'error', message: errorText(e) }))
  }
}

async function showPreview($: $, id: string) {
  const token = newToken()
  const p0 = await read($, panel)
  if (p0.phase !== 'ready') return
  const scope = p0.token
  const title = p0.docs.find(d => d.id === id)?.title ?? id
  await updatePanel($, (p): WorklogPanel =>
    p.token === scope
      ? { ...p, loadNote: null, preview: { id, title, token, phase: 'loading', text: null, page: 0, message: null } }
      : p,
  )
  const commit = (fn: (v: NonNullable<WorklogPanel['preview']>) => WorklogPanel['preview']) =>
    updatePanel($, p => (p.token === scope && p.preview?.token === token ? { ...p, preview: fn(p.preview) } : p))
  try {
    const { got } = await fetchInScope($, id)
    await commit(v => ({ ...v, phase: 'ready', title: got.title, text: got.text }))
  } catch (e) {
    await commit(v => ({ ...v, phase: 'error', message: errorText(e) }))
  }
}

async function loadIntoSession($: $) {
  const p = await read($, panel)
  const v = p.preview
  if (p.phase !== 'ready' || !v || v.phase !== 'ready' || v.text === null) return
  const note = (loadNote: string) => updatePanel($, q => (q.preview?.token === v.token ? { ...q, loadNote } : q))
  if (v.text.length > LOAD_LIMIT) {
    return void (await note(`Not loaded: the body is too large (${v.text.length} characters, limit ${LOAD_LIMIT}). Read it with /worklog-persist:load or fetch it in parts.`))
  }
  const doc = p.docs.find(d => d.id === v.id)
  if (!doc) return void (await note('Not loaded: the document is no longer in the current project.'))
  try {
    const res = await $.session.append({
      message: {
        type: 'user',
        content: [{ type: 'text', text: frameForSession({ id: v.id, title: v.title, parentId: doc.parentId, text: v.text }, doc.path) }],
      },
    })
    if (res.deny !== undefined) return void (await note(`Not loaded, the session refused it: ${res.deny}`))
    await note(`Loaded "${v.title}" (${v.id}) into the session as reference.`)
  } catch (e) {
    await note(`Not loaded: ${errorText(e)}`)
  }
}

const inFlight = (p: WorklogPanel) => p.action?.phase === 'queued' || p.action?.phase === 'dispatched'

async function pickAction($: $, verb: WorklogVerb) {
  await updatePanel($, (p): WorklogPanel => {
    if (inFlight(p) || p.phase === 'loading') return p
    const command = p.commands.find(c => c.verb === verb)?.command
    if (!command) return p
    const slug = p.activeTask?.slug ?? ''
    if (TASK_VERBS.includes(verb) && !slug) {
      return {
        ...p,
        action: { verb, command, args: '', phase: 'failed', message: `Choose a task first: ${verb} acts on one task record.`, scopeToken: p.token },
      }
    }
    const args = verb === 'off' ? 'status' : verb === 'start' || verb === 'setup' ? '' : slug
    return { ...p, action: { verb, command, args, phase: 'editing', message: null, scopeToken: p.token } }
  })
}

function argsError(verb: WorklogVerb, args: string): string | null {
  if (verb === 'off') return ['on', 'off', 'status'].includes(args) ? null : 'off takes on, off or status.'
  if (verb === 'setup') return null
  if (!args) return verb === 'start' || TASK_VERBS.includes(verb) ? `${verb} needs a task slug.` : null
  return SLUG_RE.test(args) ? null : 'A task slug is kebab-case, optionally prefixed with a ticket id (AD-163-name).'
}

async function runAction($: $) {
  let picked: WorklogPanel['action'] = null
  await updatePanel($, p => {
    picked = null
    const a = p.action
    if (!a || a.phase !== 'editing' || a.scopeToken !== p.token || p.phase === 'loading') return p
    const error = argsError(a.verb, a.args.trim())
    if (error) return { ...p, action: { ...a, message: error } }
    picked = { ...a, args: a.args.trim(), phase: 'queued', message: 'queued' }
    return { ...p, action: picked }
  })
  const a = picked as WorklogPanel['action']
  if (!a) return
  const settle = (fn: (x: NonNullable<WorklogPanel['action']>) => WorklogPanel['action']) =>
    updatePanel($, p => (p.action?.phase === 'queued' && p.action.verb === a.verb ? { ...p, action: fn(p.action) } : p))
  try {
    await $.command.run({ command: a.command, args: a.args })
    await settle(x => ({
      ...x,
      phase: 'dispatched',
      message: 'dispatched to the session. Not confirmed as written: the panel refreshes when the turn ends.',
    }))
    await updatePanel($, p => ({ ...p, isDirty: true }))
  } catch (e) {
    await settle(x => ({ ...x, phase: 'failed', message: `could not run: ${errorText(e)}` }))
  }
}

/** Opens the pane and refreshes it; the answer says whether a surface shows it. */
async function open($: $): Promise<string> {
  const opened = await $.ui.open({ id: PANE, title: TITLE })
  if (!opened.isPlaced) {
    // The pane may render later, after the project's configuration has changed.
    await updatePanel($, () => ({ ...EMPTY, token: newToken() }))
    return `The worklog panel is not shown yet (${opened.reason}). It appears when a surface can place it; press Refresh there.`
  }
  await refresh($)
  return 'Opened the worklog panel.'
}

const page = <T,>(list: T[], at: number) => {
  const pages = pageCount(list.length, LIST_PAGE)
  const index = Math.min(Math.max(at, 0), pages - 1)
  return { rows: list.slice(index * LIST_PAGE, (index + 1) * LIST_PAGE), index, pages }
}

async function updatePanel($: $, change: (p: WorklogPanel) => WorklogPanel) {
  const result = await update($, panel, change)
  await updateStatus($)
  return result
}

async function updateStatus($: $) {
  const p = await read($, panel)
  if (p.phase !== 'ready' || !p.projectId) {
    $.ui.status(undefined)
    return
  }
  const task = p.activeTask?.slug ?? 'not selected'
  const preview = p.preview?.phase === 'ready' ? ` | Preview: ${p.preview.title.replace(/\s+/g, ' ')}` : ''
  $.ui.status(`Task: ${task}${preview}`)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    const p = await read($, panel)
    // A reload or a moved session never shows another directory's project.
    if (p.cwd !== null && p.cwd !== (await $.session.cwd())) await updatePanel($, () => ({ ...EMPTY, token: newToken() }))
    await updateStatus($)
    return started
  })

  on('session.end', async ($, e, next) => {
    if (e.reason === 'clear') await updatePanel($, () => ({ ...EMPTY, token: newToken() }))
    return next(e)
  })

  on('command.run', { command: SHOW_COMMAND }, async $ => ({ text: await open($) })).catch(($, e, next) => next(e))

  on('prompt.submit', async ($, e, next) => {
    if (e.command || e.isMeta || e.text.trim().toLowerCase() !== PHRASE) return next(e)
    return { drop: await open($) }
  }).catch(($, e, next) => next(e))

  // An Outline write by the model or a command marks the snapshot stale.
  on('tool.call', { tool: /^mcp__(outline|plugin_worklog-persist_outline)__/ }, async ($, e, next) => {
    const result = await next(e)
    const name = String(e.tool).split('__').pop() ?? ''
    if (!name.startsWith('list_') && name !== 'fetch') {
      await updatePanel($, p => (p.cwd === null ? p : { ...p, isDirty: true }))
    }
    return result
  }).catch(($, e, next) => next(e))

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (e.agentId !== undefined) return done
    const p = await read($, panel)
    if (p.cwd === null || !(p.isDirty || inFlight(p))) return done
    await updatePanel($, (q): WorklogPanel =>
      inFlight(q) && q.action
        ? { ...q, action: { ...q.action, phase: 'turn-ended', message: 'the turn ended. Refreshed from Outline: read the record to see what changed.' } }
        : q,
    )
    await refresh($)
    return done
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const t = $.ui.resolve(e)
    const { Box, Text, Button } = t
    const Input = 'Input' in t ? t.Input : null
    const p = await read($, panel)
    const id = p.identity
    const tasks = p.docs.filter(d => d.kind === 'task')
    const taskPage = page(tasks, p.taskPage)
    const q = p.query.trim().toLowerCase()
    const matches = q ? p.docs.filter(d => d.path.toLowerCase().includes(q)) : p.docs.filter(d => d.kind === 'doc')
    const docPage = page(matches, p.docPage)
    const history = p.activeTask ? p.docs.filter(d => d.parentId === p.activeTask?.id) : []
    const v = p.preview
    const vPages = v?.text ? pageCount(v.text.length, PAGE_CHARS) : 1
    const vPage = Math.min(v?.page ?? 0, vPages - 1)
    const a = p.action
    const offered = p.commands.map(c => c.verb)
    const missing = VERBS.filter(verb => !offered.includes(verb))
    const set = (fn: (x: WorklogPanel) => WorklogPanel) => updatePanel($, fn)

    return (
      <Box flexDirection="column" gap={1}>
        <Box flexDirection="column">
          <Text bold>{id ? `${id.project} (${id.world}), branch ${id.branch}` : 'Worklog panel'}</Text>
          {p.persistence === 'off' && (
            <Text>Persistence is off: automatic writes are disabled. Reading here is read-only.</Text>
          )}
          {p.persistence === 'unknown' && id && <Text dimColor>Persistence state is unknown: persistence-state.sh gave no answer.</Text>}
          {p.phase === 'idle' && <Text dimColor>Not loaded for this session yet.</Text>}
          {p.phase === 'loading' && <Text dimColor>Loading from Outline...</Text>}
          {p.message && <Text>{p.message}</Text>}
          <Button key="refresh" label={p.isFailure ? 'Retry' : 'Refresh'} onPress={() => refresh($)} />
        </Box>

        {p.phase === 'ready' && p.projectId && (
          <Box flexDirection="column">
            <Text bold>Tasks</Text>
            {tasks.length === 0 ? (
              <Text dimColor>No task records in Tasks yet.</Text>
            ) : (
              <Text dimColor>
                Tasks {taskPage.index * LIST_PAGE + 1}-{taskPage.index * LIST_PAGE + taskPage.rows.length} of {tasks.length} tasks
              </Text>
            )}
            {taskPage.rows.map(d => (
              <Button key={`task:${d.id}`} plain onPress={() => chooseTask($, d.id, d.title)}>
                {p.activeTask?.id === d.id ? `> ${d.title}` : d.title}
              </Button>
            ))}
            {taskPage.pages > 1 && (
              <Box flexDirection="row" gap={1}>
                <Button key="tasks-prev" label="Previous" onPress={() => set(x => ({ ...x, taskPage: Math.max(0, taskPage.index - 1) }))} />
                <Button key="tasks-next" label="Next" onPress={() => set(x => ({ ...x, taskPage: Math.min(taskPage.pages - 1, taskPage.index + 1) }))} />
              </Box>
            )}
            {!p.activeTask ? (
              <Text dimColor>No active task chosen. Pick one above; none is guessed.</Text>
            ) : (
              <Box flexDirection="column">
                <Text>Active task: {p.activeTask.slug}</Text>
                {p.taskDetail?.phase === 'loading' && <Text dimColor>Reading the record...</Text>}
                {p.taskDetail?.phase === 'error' && <Text>Could not read the record: {p.taskDetail.message}</Text>}
                {p.taskDetail?.phase === 'ready' && <Text>Status: {p.taskDetail.status ?? '(no Status section)'}</Text>}
                {p.taskDetail?.phase === 'ready' && <Text>Next action: {p.taskDetail.nextAction ?? '(no Next action section)'}</Text>}
                {history.length === 0 ? (
                  <Text dimColor>No checkpoints or handoffs under this record.</Text>
                ) : (
                  history.map(d => (
                    <Button key={`hist:${d.id}`} plain onPress={() => showPreview($, d.id)}>
                      {d.title}
                    </Button>
                  ))
                )}
              </Box>
            )}
          </Box>
        )}

        {p.phase === 'ready' && p.projectId && (
          <Box flexDirection="column">
            <Text bold>Documents</Text>
            {Input && (
              <Input
                key="query"
                label="Filter by title"
                value={p.query}
                onInput={value => set(x => ({ ...x, query: value, docPage: 0 }))}
                onSubmit={value => set(x => ({ ...x, query: value, docPage: 0 }))}
              />
            )}
            <Text dimColor>
              {matches.length === 0 ? 'No matching documents in this project.' : `${matches.length} documents, page ${docPage.index + 1} of ${docPage.pages}`}
            </Text>
            {docPage.rows.map(d => (
              <Button key={`doc:${d.id}`} plain onPress={() => showPreview($, d.id)}>
                {d.path}
              </Button>
            ))}
            {docPage.pages > 1 && (
              <Box flexDirection="row" gap={1}>
                <Button key="docs-prev" label="Previous" onPress={() => set(x => ({ ...x, docPage: Math.max(0, docPage.index - 1) }))} />
                <Button key="docs-next" label="Next" onPress={() => set(x => ({ ...x, docPage: Math.min(docPage.pages - 1, docPage.index + 1) }))} />
              </Box>
            )}
          </Box>
        )}

        {v && (
          <Box flexDirection="column">
            <Text bold>Preview: {v.title}</Text>
            <Text dimColor>Outline id {v.id}. Shown here only; not in the conversation.</Text>
            {v.phase === 'loading' && <Text dimColor>Reading...</Text>}
            {v.phase === 'error' && <Text>Could not show it: {v.message}</Text>}
            {v.phase === 'ready' && v.text !== null && (
              <Text wrap="wrap">{v.text.slice(vPage * PAGE_CHARS, (vPage + 1) * PAGE_CHARS)}</Text>
            )}
            {v.phase === 'ready' && <Text dimColor>Page {vPage + 1} of {vPages}</Text>}
            <Box flexDirection="row" gap={1}>
              {vPage > 0 && (
                <Button key="preview-prev" label="Previous page" onPress={() => set(x => (x.preview ? { ...x, preview: { ...x.preview, page: vPage - 1 } } : x))} />
              )}
              {vPage < vPages - 1 && (
                <Button key="preview-next" label="Next page" onPress={() => set(x => (x.preview ? { ...x, preview: { ...x.preview, page: vPage + 1 } } : x))} />
              )}
              {v.phase === 'ready' && <Button key="load" label="Load into session" onPress={() => loadIntoSession($)} />}
              <Button key="preview-close" label="Close" onPress={() => set(x => ({ ...x, preview: null, loadNote: null }))} />
            </Box>
            {p.loadNote && <Text>{p.loadNote}</Text>}
          </Box>
        )}

        <Box flexDirection="column">
          <Text bold>Actions</Text>
          <Box flexDirection="row" gap={1} flexWrap="wrap">
            {p.phase !== 'loading' && p.commands.map(c => (
              <Button key={`act:${c.verb}`} label={c.verb} onPress={() => pickAction($, c.verb)} />
            ))}
          </Box>
          {missing.length > 0 && p.commands.length > 0 && <Text dimColor>unavailable: {missing.join(', ')}</Text>}
          {p.commands.length === 0 && p.phase !== 'loading' && <Text dimColor>No worklog-persist commands are listed in this session.</Text>}
          {a && a.phase === 'editing' && (
            <Box flexDirection="column">
              {Input ? (
                <Input
                  key="args"
                  label={`/${a.command} arguments`}
                  value={a.args}
                  onInput={value => set(x => (x.action?.phase === 'editing' ? { ...x, action: { ...x.action, args: value, message: null } } : x))}
                  onSubmit={value => set(x => (x.action?.phase === 'editing' ? { ...x, action: { ...x.action, args: value, message: null } } : x))}
                />
              ) : (
                <Text>Arguments: {a.args || '(none)'}</Text>
              )}
              <Box flexDirection="row" gap={1}>
                <Button key="run" label={`Run /${a.command}`} variant="primary" onPress={() => runAction($)} />
                <Button key="cancel" label="Cancel" onPress={() => set(x => (x.action?.phase === 'editing' ? { ...x, action: null } : x))} />
              </Box>
            </Box>
          )}
          {a?.message && (
            <Text>
              {a.verb}: {a.message}
            </Text>
          )}
        </Box>
      </Box>
    )
  })
}
