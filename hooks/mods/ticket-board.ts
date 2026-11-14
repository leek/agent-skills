// Pure helpers for the ticket board: the per-ticket status of a multi-ticket run
// (implement-spec, implement <spec> all, wayfinder <map> all), as the
// mcp__leek-skills__ticket_board tool reports it, then the review stage and its findings
// once the tickets are built, and the work still open when the run ends. The skills own
// the statuses; this only merges each update and says how a row reads.

import type {
  BoardFinding,
  BoardKind,
  BoardOpenItem,
  BoardTicket,
  FindingStatus,
  OpenKind,
  TicketBoard,
  TicketStatus,
} from '../../types'

export const STATUSES: readonly TicketStatus[] = [
  'blocked',
  'ready',
  'running',
  'fixing',
  'built',
  'merged',
  'resolved',
  'released',
  'awaiting-deploy',
  'closed',
  'not-built',
  'skipped',
]

export const FINDING_STATUSES: readonly FindingStatus[] = ['open', 'fixing', 'fixed', 'asking', 'deferred']

export const OPEN_KINDS: readonly OpenKind[] = ['not-shipped', 'not-started', 'not-verified', 'your-decision', 'later']

const UNTRACKED = 'untracked'

const KINDS: readonly BoardKind[] = ['spec', 'map']

export type BoardUpdate = {
  board: string
  kind: BoardKind
  tickets: { number: string; title?: string; status: TicketStatus; note?: string }[]
  stage?: string
  findings?: { id: string; title?: string; status: FindingStatus; note?: string }[]
  open?: { id: string; title?: string; kind: OpenKind; where?: string; done?: boolean }[]
}

/** The input schema the model reads; kept beside the type it describes. */
export const SCHEMA = {
  type: 'object',
  properties: {
    board: { type: 'string', description: 'The spec or map slug (.scratch/<slug>/).' },
    kind: { type: 'string', enum: KINDS },
    stage: {
      type: 'string',
      description: 'Once the tickets are built, the step the run is in, e.g. "review round 1", "fix pass", "final checks".',
    },
    tickets: {
      type: 'array',
      description: 'Tickets whose status changed; the first call lists every in-scope ticket with its title.',
      items: {
        type: 'object',
        properties: {
          number: { type: 'string', description: 'The ticket number, e.g. "03".' },
          title: { type: 'string' },
          status: {
            type: 'string',
            enum: STATUSES,
            description:
              'not-built: an open ticket this run leaves alone (the note says why); it counts as open work. skipped: closed elsewhere or ruled out for good.',
          },
          note: { type: 'string', description: 'A few words: who blocks it, why it failed, the commit or merge SHA.' },
        },
        required: ['number', 'status'],
      },
    },
    findings: {
      type: 'array',
      description: 'Review findings whose status changed; each joins with its title on its first call.',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string', description: 'A key that stays the same across calls, e.g. "3". Never shown.' },
          title: { type: 'string', description: 'What is wrong, in plain words a reader new to the run understands.' },
          status: { type: 'string', enum: FINDING_STATUSES },
          note: { type: 'string', description: 'A few words: the fix commit, the question asked, why it waits.' },
        },
        required: ['id', 'status'],
      },
    },
    open: {
      type: 'array',
      description:
        'Work still open after this run, drawn as "Open after this run"; send the entries that changed, each with its title and where on its first call.',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string', description: 'A key that stays the same across calls. Never shown.' },
          title: { type: 'string', description: 'What is open, in plain words a reader new to the run understands.' },
          kind: { type: 'string', enum: OPEN_KINDS },
          where: {
            type: 'string',
            description: 'Where it is tracked: a ticket path, a decision record, a pull request, or the literal "untracked".',
          },
          done: { type: 'boolean', description: 'true once it is resolved; the pane strikes it.' },
        },
        required: ['id', 'kind'],
      },
    },
  },
  required: ['board', 'kind'],
} as const

export function parseUpdate(input: Record<string, unknown>): BoardUpdate | string {
  const board = typeof input.board === 'string' ? input.board.trim() : ''
  const kind = input.kind as BoardKind
  const isList = (v: unknown) => v === undefined || Array.isArray(v)
  if (board === '' || !KINDS.includes(kind) || !isList(input.tickets) || !isList(input.findings) || !isList(input.open)) {
    return `board (string) and kind (${KINDS.join(' or ')}) are required; tickets, findings and open are arrays.`
  }
  const tickets: BoardUpdate['tickets'] = []
  for (const raw of (input.tickets ?? []) as unknown[]) {
    const t = (raw ?? {}) as Record<string, unknown>
    const status = t.status as TicketStatus
    if (typeof t.number !== 'string' || t.number === '' || !STATUSES.includes(status)) {
      return `Each ticket needs a number and a status of ${STATUSES.join(', ')}.`
    }
    tickets.push({
      number: t.number,
      status,
      title: typeof t.title === 'string' ? t.title : undefined,
      note: typeof t.note === 'string' ? t.note : undefined,
    })
  }
  const findings: BoardUpdate['findings'] = []
  for (const raw of (input.findings ?? []) as unknown[]) {
    const f = (raw ?? {}) as Record<string, unknown>
    const status = f.status as FindingStatus
    if (typeof f.id !== 'string' || f.id === '' || !FINDING_STATUSES.includes(status)) {
      return `Each finding needs an id and a status of ${FINDING_STATUSES.join(', ')}.`
    }
    findings.push({
      id: f.id,
      status,
      title: typeof f.title === 'string' ? f.title : undefined,
      note: typeof f.note === 'string' ? f.note : undefined,
    })
  }
  const open: NonNullable<BoardUpdate['open']> = []
  for (const raw of (input.open ?? []) as unknown[]) {
    const o = (raw ?? {}) as Record<string, unknown>
    const openKind = o.kind as OpenKind
    if (typeof o.id !== 'string' || o.id === '' || !OPEN_KINDS.includes(openKind)) {
      return `Each open entry needs an id and a kind of ${OPEN_KINDS.join(', ')}.`
    }
    open.push({
      id: o.id,
      kind: openKind,
      title: typeof o.title === 'string' ? o.title : undefined,
      where: typeof o.where === 'string' ? o.where : undefined,
      done: typeof o.done === 'boolean' ? o.done : undefined,
    })
  }
  const stage = typeof input.stage === 'string' ? input.stage.trim() : undefined

  return { board, kind, tickets, stage, findings, open }
}

/** Upserts by ticket number; a new slug or kind starts a new board. */
export function apply(previous: TicketBoard | null, change: BoardUpdate, now: number): TicketBoard {
  const isSame = previous?.slug === change.board && previous.kind === change.kind
  const tickets: BoardTicket[] = isSame ? [...previous.tickets] : []
  for (const t of change.tickets) {
    const at = tickets.findIndex(one => one.number === t.number)
    const old = at === -1 ? undefined : tickets[at]
    const next: BoardTicket = {
      number: t.number,
      title: t.title ?? old?.title ?? '',
      status: t.status,
      // A status change without a note clears the old one; it described the old status.
      note: t.note ?? (old?.status === t.status ? old.note : ''),
    }
    if (old === undefined) {
      tickets.push(next)
    } else {
      tickets[at] = next
    }
  }
  tickets.sort((a, b) => a.number.localeCompare(b.number, undefined, { numeric: true }))

  // Findings keep the order the review reported them in.
  // A board saved before findings existed has none.
  const findings: BoardFinding[] = isSame ? [...(previous.findings ?? [])] : []
  for (const f of change.findings ?? []) {
    const at = findings.findIndex(one => one.id === f.id)
    const old = at === -1 ? undefined : findings[at]
    const next: BoardFinding = {
      id: f.id,
      title: f.title ?? old?.title ?? '',
      status: f.status,
      note: f.note ?? (old?.status === f.status ? old.note : ''),
    }
    if (old === undefined) {
      findings.push(next)
    } else {
      findings[at] = next
    }
  }
  const stage = change.stage ?? (isSame ? (previous.stage ?? '') : '')

  // Open entries keep the order the run listed them in.
  // A board saved before the open list existed has none.
  const open: BoardOpenItem[] = isSame ? [...(previous.open ?? [])] : []
  for (const o of change.open ?? []) {
    const at = open.findIndex(one => one.id === o.id)
    const old = at === -1 ? undefined : open[at]
    const next: BoardOpenItem = {
      id: o.id,
      title: o.title ?? old?.title ?? '',
      kind: o.kind,
      // An entry that names no tracking place has none.
      where: (o.where ?? old?.where ?? '').trim() || UNTRACKED,
      done: o.done ?? old?.done ?? false,
    }
    if (old === undefined) {
      open.push(next)
    } else {
      open[at] = next
    }
  }

  return { slug: change.board, kind: change.kind, tickets, stage, findings, open, updatedAt: now }
}

const DONE = new Set<TicketStatus>(['built', 'merged', 'resolved', 'closed'])

export const title = (board: TicketBoard) => `${board.kind === 'map' ? 'Map' : 'Spec'}: ${board.slug}`

export function tally(board: TicketBoard): string {
  const count = (s: TicketStatus) => board.tickets.filter(t => t.status === s).length
  const done = board.tickets.filter(t => DONE.has(t.status)).length
  // Only a skipped ticket leaves the total: not-built and released tickets are open work.
  const parts = [`${done} of ${board.tickets.length - count('skipped')} done`]
  for (const s of ['not-built', 'running', 'fixing', 'ready', 'blocked', 'released', 'awaiting-deploy'] as const) {
    if (count(s) > 0) parts.push(`${count(s)} ${s === 'not-built' ? 'not built' : s}`)
  }

  return parts.join(' · ')
}

export function findingTally(board: TicketBoard): string {
  const count = (s: FindingStatus) => board.findings.filter(f => f.status === s).length
  const parts = [`${count('fixed')} of ${board.findings.length} fixed`]
  for (const s of ['fixing', 'open', 'asking', 'deferred'] as const) {
    if (count(s) > 0) parts.push(`${count(s)} ${s}`)
  }

  return parts.join(' · ')
}

export const isUntracked = (o: BoardOpenItem) => o.where.toLowerCase() === UNTRACKED

/** The open list's count, or empty when the run has sent no list. */
export function openTally(board: TicketBoard): string {
  if (board.open.length === 0) return ''
  const left = board.open.filter(o => !o.done)
  const untracked = left.filter(isUntracked).length

  return `${left.length} open after this run${untracked > 0 ? ` (${untracked} untracked)` : ''}`
}

/** The pane's header: the ticket count, then the open list's. */
export const header = (board: TicketBoard) => [tally(board), openTally(board)].filter(part => part !== '').join(' · ')

/** The tool's one-line summary: the header, then the stage and findings once a review runs. */
export const summary = (board: TicketBoard) =>
  [header(board), board.stage, board.findings.length > 0 ? findingTally(board) : '']
    .filter(part => part !== '')
    .join(' · ')

export const ticketMark = (s: TicketStatus) =>
  ({
    blocked: '○',
    ready: '●',
    running: '◐',
    fixing: '↻',
    built: '✓',
    merged: '✓',
    resolved: '✓',
    closed: '✓',
    released: '⏸',
    'awaiting-deploy': '◇',
    'not-built': '□',
    skipped: '–',
  })[s]

const WAITING = new Set<TicketStatus>(['fixing', 'released', 'awaiting-deploy', 'not-built'])

export const ticketColor = (s: TicketStatus) =>
  s === 'running' ? 'suggestion' : DONE.has(s) ? 'success' : WAITING.has(s) ? 'warning' : undefined

export const findingMark = (s: FindingStatus) =>
  ({ open: '○', fixing: '◐', fixed: '✓', asking: '?', deferred: '⏸' })[s]

export const findingColor = (s: FindingStatus) =>
  s === 'fixing' ? 'suggestion' : s === 'fixed' ? 'success' : s === 'asking' || s === 'deferred' ? 'warning' : undefined

export const openMark = (o: BoardOpenItem) => (o.done ? '✓' : isUntracked(o) ? '!' : '○')

export const openColor = (o: BoardOpenItem) => (o.done ? 'success' : isUntracked(o) ? 'error' : 'warning')

/** `your-decision` reads as `your decision`. */
export const openLabel = (k: OpenKind) => k.replace('-', ' ')
