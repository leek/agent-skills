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
  /** `delivery: true`: the spec's last ticket, which proves the spec shipped. */
  delivery: boolean
  /** Non-empty lines under a spec's `## Open Questions`; 0 for every other kind. */
  openQuestions: number
}

export type ScratchEffort = {
  slug: string
  files: ScratchFile[]
  lastChangeMs: number
  state: 'open' | 'done' | 'mismatched'
  isStale: boolean
  /** Open tickets and decisions ready to start: blockers all closed, unclaimed, not `in-progress`. */
  frontier: string[]
  next: string
}

export type ScratchBoard = {
  root: string
  scannedAt: number
  efforts: ScratchEffort[]
}

export type TicketStatus =
  | 'blocked'
  | 'ready'
  | 'running'
  | 'fixing'
  | 'built'
  | 'merged'
  | 'resolved'
  | 'released'
  | 'awaiting-deploy'
  | 'closed'
  /** Open, and left alone by this run; the note says why. Counts as open work. */
  | 'not-built'
  /** Closed elsewhere or ruled out for good; leaves the count. */
  | 'skipped'

export type BoardKind = 'spec' | 'map'

export type BoardTicket = {
  /** Leading ticket number, e.g. `03`. */
  number: string
  title: string
  status: TicketStatus
  note: string
}

export type FindingStatus = 'open' | 'fixing' | 'fixed' | 'asking' | 'deferred'

/** One review finding the run is fixing after its tickets merged. */
export type BoardFinding = {
  /** A stable key across updates; never shown. */
  id: string
  title: string
  status: FindingStatus
  note: string
}

export type OpenKind = 'not-shipped' | 'not-started' | 'not-verified' | 'your-decision' | 'later'

/** One piece of work still open when the run ends. */
export type BoardOpenItem = {
  /** A stable key across updates; never shown. */
  id: string
  title: string
  kind: OpenKind
  /** Where it is tracked: a ticket path, a decision record, a pull request, or `untracked`. */
  where: string
  /** Resolved since it was listed; the pane strikes it. */
  done: boolean
}

/** A multi-ticket run (implement-spec, implement all, wayfinder all) as the ticket_board tool last reported it. */
export type TicketBoard = {
  slug: string
  kind: BoardKind
  tickets: BoardTicket[]
  /** The step after the build, e.g. `review round 1`; empty while tickets build. */
  stage: string
  findings: BoardFinding[]
  /** The "Open after this run" list; empty until the run sends one. */
  open: BoardOpenItem[]
  updatedAt: number
}

export type Worker = {
  id: string
  /** The Agent call's `name`, or empty; board runs name a ticket's worker `<slug>--<NN>`. */
  name: string
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
      tickets: TicketBoard | null
    }
  }
}
