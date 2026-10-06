// The leek-skills mod's $.state contract (hooks/mods/).

export type ScratchKind = 'map' | 'spec' | 'decision' | 'ticket' | 'request'

export type ScratchFile = {
  /** Path relative to the effort, e.g. `tickets/02-login.md`. */
  path: string
  kind: ScratchKind
  /** Leading ticket number (`02`), or empty for map, spec, and requests. */
  number: string
  title: string
  /** Lowercased status, or empty when the file has none. */
  status: string
  claimedBy: string
  blockedBy: string[]
}

export type ScratchEffort = {
  slug: string
  files: ScratchFile[]
  lastChangeMs: number
  state: 'open' | 'done' | 'mismatched'
  isStale: boolean
  /** Open files whose blockers are all closed, unclaimed, ticket or decision. */
  frontier: string[]
  next: string
}

export type ScratchBoard = {
  root: string
  scannedAt: number
  efforts: ScratchEffort[]
}

export type Worker = {
  id: string
  type: string
  description: string
  startedAt: number
  endedAt: number
  tools: number
  lastTool: string
  outcome: 'running' | 'answer' | 'aborted' | 'error' | 'refusal'
}

declare module 'claude-code' {
  interface PluginState {
    'leek-skills': {
      scratch: ScratchBoard | null
      workers: Worker[]
      isWorkersHidden: boolean
    }
  }
}
