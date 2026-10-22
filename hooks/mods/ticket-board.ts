// Pure helpers for the ticket board: the per-ticket status of a multi-ticket run
// (implement-spec, implement <spec> all, wayfinder <map> all), as the
// mcp__leek-skills__ticket_board tool reports it. The skills own the statuses; this only
// merges each update and says how a row reads.

import type { BoardKind, BoardTicket, TicketBoard, TicketStatus } from '../../types'

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

const KINDS: readonly BoardKind[] = ['spec', 'map']

export type BoardUpdate = {
  board: string
  kind: BoardKind
  tickets: { number: string; title?: string; status: TicketStatus; note?: string }[]
}

/** The input schema the model reads; kept beside the type it describes. */
export const SCHEMA = {
  type: 'object',
  properties: {
    board: { type: 'string', description: 'The spec or map slug (.scratch/<slug>/).' },
    kind: { type: 'string', enum: KINDS },
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
  },
  required: ['board', 'kind', 'tickets'],
} as const

export function parseUpdate(input: Record<string, unknown>): BoardUpdate | string {
  const board = typeof input.board === 'string' ? input.board.trim() : ''
  const kind = input.kind as BoardKind
  if (board === '' || !KINDS.includes(kind) || !Array.isArray(input.tickets)) {
    return `board (string), kind (${KINDS.join(' or ')}) and tickets (array) are required.`
  }
  const tickets: BoardUpdate['tickets'] = []
  for (const raw of input.tickets as unknown[]) {
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

  return { board, kind, tickets }
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

  return { slug: change.board, kind: change.kind, tickets, updatedAt: now }
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
