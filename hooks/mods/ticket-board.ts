// Pure helpers for the ticket board: the per-ticket status of a multi-ticket run
// (implement-spec, implement <spec> all, wayfinder <map> all), as the
// mcp__leek-skills__ticket_board tool reports it, then the review stage and its findings
// once the tickets are built. The skills own the statuses; this only merges each update
// and says how a row reads.

import type { BoardFinding, BoardKind, BoardTicket, FindingStatus, TicketBoard, TicketStatus } from '../../types'

export const STATUSES: readonly TicketStatus[] = [
  'blocked',
  'ready',
  'running',
  'fixing',
  'built',
  'merged',
  'resolved',
  'released',
  'closed',
  'skipped',
]

export const FINDING_STATUSES: readonly FindingStatus[] = ['open', 'fixing', 'fixed', 'asking', 'deferred']

const KINDS: readonly BoardKind[] = ['spec', 'map']

export type BoardUpdate = {
  board: string
  kind: BoardKind
  tickets: { number: string; title?: string; status: TicketStatus; note?: string }[]
  stage?: string
  findings?: { id: string; title?: string; status: FindingStatus; note?: string }[]
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
          status: { type: 'string', enum: STATUSES },
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
  },
  required: ['board', 'kind'],
} as const

export function parseUpdate(input: Record<string, unknown>): BoardUpdate | string {
  const board = typeof input.board === 'string' ? input.board.trim() : ''
  const kind = input.kind as BoardKind
  const isList = (v: unknown) => v === undefined || Array.isArray(v)
  if (board === '' || !KINDS.includes(kind) || !isList(input.tickets) || !isList(input.findings)) {
    return `board (string) and kind (${KINDS.join(' or ')}) are required; tickets and findings are arrays.`
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
  const stage = typeof input.stage === 'string' ? input.stage.trim() : undefined

  return { board, kind, tickets, stage, findings }
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

  return { slug: change.board, kind: change.kind, tickets, stage, findings, updatedAt: now }
}

const DONE = new Set<TicketStatus>(['built', 'merged', 'resolved', 'closed'])

export const title = (board: TicketBoard) => `${board.kind === 'map' ? 'Map' : 'Spec'}: ${board.slug}`

export function tally(board: TicketBoard): string {
  const count = (s: TicketStatus) => board.tickets.filter(t => t.status === s).length
  const done = board.tickets.filter(t => DONE.has(t.status)).length
  const parts = [`${done} of ${board.tickets.length - count('skipped')} done`]
  for (const s of ['running', 'fixing', 'ready', 'blocked', 'released'] as const) {
    if (count(s) > 0) parts.push(`${count(s)} ${s}`)
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

/** The tool's one-line summary: tickets, then the stage and findings once a review runs. */
export const summary = (board: TicketBoard) =>
  [tally(board), board.stage, board.findings.length > 0 ? findingTally(board) : '']
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
    skipped: '–',
  })[s]

export const ticketColor = (s: TicketStatus) =>
  s === 'running' ? 'suggestion' : DONE.has(s) ? 'success' : s === 'fixing' || s === 'released' ? 'warning' : undefined

export const findingMark = (s: FindingStatus) =>
  ({ open: '○', fixing: '◐', fixed: '✓', asking: '?', deferred: '⏸' })[s]

export const findingColor = (s: FindingStatus) =>
  s === 'fixing' ? 'suggestion' : s === 'fixed' ? 'success' : s === 'asking' || s === 'deferred' ? 'warning' : undefined
