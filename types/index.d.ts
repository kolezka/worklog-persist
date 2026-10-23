// State contract of the native worklog panel (hooks/register.tsx).
// One value, `panel`, held for the session by the engine. Change the shape
// tag in hooks/register.tsx when a field changes, so a reload declines what
// older code stored.

/** What scripts/resolve_context.py prints, the fields the panel reads. */
export type WorklogIdentity = {
  repo: string
  repoRoot: string
  project: string
  world: string
  worldSource: string
  ignored: boolean
  branch: string
  kbPath: string | null
  tasksPath: string | null
  configError: string | null
}

/** One document inside the resolved project folder. */
export type WorklogDoc = {
  id: string
  title: string
  parentId: string
  /** Titles from the project folder down to this document, joined by `/`. */
  path: string
  kind: 'task' | 'history' | 'doc'
}

export type WorklogPhase = 'idle' | 'loading' | 'ready' | 'error'

export type WorklogVerb =
  | 'load'
  | 'start'
  | 'checkpoint'
  | 'handoff'
  | 'complete'
  | 'dry-run'
  | 'setup'
  | 'off'

export type WorklogAction = {
  verb: WorklogVerb
  /** The command name `$.command.list()` reported for this verb. */
  command: string
  args: string
  /** queued: handed to the engine; dispatched: the engine accepted it. Neither means Outline was written. */
  phase: 'editing' | 'queued' | 'dispatched' | 'turn-ended' | 'failed'
  message: string | null
  /** The refresh token current when it was picked; it cannot run under another. */
  scopeToken: string
}

export type WorklogPanel = {
  /** Directory the snapshot was resolved from. A snapshot for another cwd is never shown. */
  cwd: string | null
  /** Changes on every refresh; a response carrying an older token is dropped. */
  token: string
  phase: WorklogPhase
  /** Why the snapshot is not usable: an error, or a stop such as an ignored repo. */
  message: string | null
  /** True when the message is a failure, false for a deliberate stop (ignored, unresolved, missing folder). */
  isFailure: boolean
  identity: WorklogIdentity | null
  persistence: 'on' | 'off' | 'unknown'
  /** Outline tool prefix in use, e.g. `mcp__outline__`. */
  toolPrefix: string | null
  projectId: string | null
  docs: WorklogDoc[]
  /** Chosen by the person, never guessed. Separate from `preview`. */
  activeTask: { id: string; slug: string } | null
  taskDetail: {
    id: string
    token: string
    phase: WorklogPhase
    status: string | null
    nextAction: string | null
    message: string | null
  } | null
  /** Lifecycle commands `$.command.list()` reported, by verb. A verb not listed is not offered. */
  commands: { verb: WorklogVerb; command: string }[]
  query: string
  taskPage: number
  docPage: number
  preview: {
    id: string
    title: string
    token: string
    phase: WorklogPhase
    text: string | null
    page: number
    message: string | null
  } | null
  loadNote: string | null
  action: WorklogAction | null
  /** An Outline tool ran or an action was dispatched since the last refresh. */
  isDirty: boolean
  /**
   * The selection set aside while a refresh confirms the scope. It comes back
   * only when a later refresh resolves the same kb_path and the ids are still in it.
   */
  held: { kbPath: string; activeTask: { id: string; slug: string } | null; previewId: string | null } | null
}

declare module 'claude-code' {
  interface PluginState {
    'worklog-persist': { panel: Shaped<WorklogPanel> }
  }
}
