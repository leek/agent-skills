// Reads .scratch/ into a board: the deterministic half of the scratch-status skill.
// Commit-ancestry checks stay in the skill; this only reads frontmatter and mtimes.

import type { ScratchBoard, ScratchEffort, ScratchFile, ScratchKind } from '../../types'

export type Entry = { name: string; kind: 'file' | 'dir' | 'other'; mtimeMs: number }

export type Reader = {
  list: (path: string) => Promise<readonly Entry[]>
  read: (path: string) => Promise<string>
}

const CLOSED = new Set(['closed', 'wontfix'])
const STALE_MS = 30 * 24 * 60 * 60 * 1000
const TICKET_DIRS: Record<string, ScratchKind> = {
  decisions: 'decision',
  tickets: 'ticket',
  issues: 'ticket',
}

export const isClosed = (file: ScratchFile) => CLOSED.has(file.status)

export function parseFile(path: string, kind: ScratchKind, text: string): ScratchFile {
  const name = path.split('/').pop() ?? path
  const number = kind === 'decision' || kind === 'ticket' ? (name.match(/^(\d+)/)?.[1] ?? '') : ''
  const front = text.match(/^---\r?\n([\s\S]*?)\r?\n---/)?.[1] ?? ''
  const field = (key: string) =>
    front.match(new RegExp(`^${key}:[ \\t]*(.*)$`, 'm'))?.[1]?.trim().replace(/^["']|["']$/g, '') ?? ''

  let status = field('status')
  if (status === '') {
    const head = text.split('\n').slice(0, 30).join('\n')
    status = head.match(/^\*\*Status:\*\*\s*(.+)$/m)?.[1] ?? head.match(/^Status:\s*(.+)$/m)?.[1] ?? ''
  }

  return {
    path,
    kind,
    number,
    title: field('title') || text.match(/^#\s+(.+)$/m)?.[1]?.trim() || name.replace(/\.md$/, ''),
    status: (status.trim().replace(/[`*]/g, '').split(/\s/)[0] ?? '').toLowerCase(),
    claimedBy: field('claimed-by'),
    blockedBy: parseList(front, 'blocked-by'),
  }
}

function parseList(front: string, key: string): string[] {
  const inline = front.match(new RegExp(`^${key}:[ \\t]*\\[(.*)\\]`, 'm'))
  if (inline) {
    return (inline[1] ?? '').split(',').map(s => s.trim().replace(/^["']|["']$/g, '')).filter(Boolean)
  }
  const block = front.match(new RegExp(`^${key}:[ \\t]*\\r?\\n((?:[ \\t]*-.*\\r?\\n?)+)`, 'm'))
  if (block) {
    return (block[1] ?? '').split('\n').map(s => s.replace(/^\s*-\s*/, '').trim()).filter(Boolean)
  }
  const bare = front.match(new RegExp(`^${key}:[ \\t]*(\\S.*)$`, 'm'))?.[1]

  return bare ? bare.split(',').map(s => s.trim()).filter(Boolean) : []
}

export function classify(slug: string, files: ScratchFile[], lastChangeMs: number, now: number): ScratchEffort {
  const at = (path: string) => `.scratch/${slug}/${path}`
  const byKind = (kind: ScratchKind) => files.filter(f => f.kind === kind)
  const open = files.filter(f => !isClosed(f))
  const isBlocked = (file: ScratchFile) =>
    file.blockedBy.some(n => {
      const blocker = files.find(f => f.kind === file.kind && f.number === n.padStart(file.number.length, '0'))
      return blocker === undefined || !isClosed(blocker)
    })
  const frontier = open
    .filter(f => (f.kind === 'ticket' || f.kind === 'decision') && f.claimedBy === '' && !isBlocked(f))
    .sort((a, b) => a.number.localeCompare(b.number))
    .map(f => f.path)

  const base = { slug, files, lastChangeMs, frontier, isStale: false }
  const mismatch = findMismatch(files)
  if (mismatch !== '') {
    return { ...base, state: 'mismatched', next: mismatch }
  }
  if (open.length === 0) {
    return { ...base, state: 'done', next: '/scratch-cleanup' }
  }

  const map = byKind('map')[0]
  const spec = byKind('spec')[0]
  const tickets = byKind('ticket')
  const decisions = byKind('decision')
  const first = frontier[0]
  let next = ''
  if (first !== undefined) {
    next = first.startsWith('decisions/') ? `/grill-me ${at(first)}` : `/implement ${at(first)}`
  } else if (byKind('request').some(f => !isClosed(f))) {
    next = '/triage'
  } else if (map && !isClosed(map) && decisions.length === 0) {
    next = `/wayfinder ${at(map.path)}`
  } else if (map && !isClosed(map) && decisions.every(isClosed) && !spec) {
    next = '/to-spec'
  } else if (spec && tickets.length === 0) {
    next = `/to-tickets ${at(spec.path)}`
  } else {
    const claimed = open.filter(f => f.claimedBy !== '').map(f => `${f.number || f.path} by ${f.claimedBy}`)
    next = claimed.length > 0 ? `waiting on ${claimed.join(', ')}` : 'everything open is blocked'
  }

  return { ...base, state: 'open', isStale: now - lastChangeMs > STALE_MS, next }
}

function findMismatch(files: ScratchFile[]): string {
  const unread = files.find(f => f.status === '')
  if (unread) {
    return `no readable status: ${unread.path}`
  }
  const spec = files.find(f => f.kind === 'spec')
  const tickets = files.filter(f => f.kind === 'ticket')
  if (spec && !isClosed(spec) && spec.status !== 'in-progress' && tickets.length > 0 && tickets.every(isClosed)) {
    return `spec still ${spec.status} while every ticket is closed`
  }
  const map = files.find(f => f.kind === 'map')
  if (map && !isClosed(map) && spec) {
    return 'map still open though spec.md exists'
  }

  return ''
}

const RANK = { open: 0, mismatched: 3, done: 4 } as const

function rank(effort: ScratchEffort): number {
  if (effort.state !== 'open') {
    return RANK[effort.state]
  }
  if (effort.isStale) {
    return 2
  }

  return effort.frontier.length > 0 ? 0 : 1
}

export async function scan(fs: Reader, root: string, now: number, only = ''): Promise<ScratchBoard> {
  const efforts: ScratchEffort[] = []
  const dirs = (await fs.list(root)).filter(
    d => d.kind === 'dir' && d.name !== 'research' && !d.name.startsWith('.') && (only === '' || d.name === only),
  )

  for (const dir of dirs) {
    const base = `${root}/${dir.name}`
    const found: { path: string; kind: ScratchKind; mtimeMs: number }[] = []
    for (const entry of await fs.list(base)) {
      if (entry.kind === 'file' && entry.name.endsWith('.md')) {
        const kind: ScratchKind = entry.name === 'map.md' ? 'map' : entry.name === 'spec.md' ? 'spec' : 'request'
        found.push({ path: entry.name, kind, mtimeMs: entry.mtimeMs })
      } else if (entry.kind === 'dir' && TICKET_DIRS[entry.name] !== undefined) {
        const kind = TICKET_DIRS[entry.name] as ScratchKind
        for (const inner of await fs.list(`${base}/${entry.name}`)) {
          if (inner.kind === 'file' && inner.name.endsWith('.md')) {
            found.push({ path: `${entry.name}/${inner.name}`, kind, mtimeMs: inner.mtimeMs })
          }
        }
      }
    }

    const files: ScratchFile[] = []
    for (const f of found) {
      const parsed = parseFile(f.path, f.kind, await fs.read(`${base}/${f.path}`))
      // A loose markdown file with no status is a note, not a triage request.
      if (f.kind !== 'request' || parsed.status !== '') {
        files.push(parsed)
      }
    }
    if (files.length > 0) {
      const lastChangeMs = Math.max(...found.map(f => f.mtimeMs))
      efforts.push(classify(dir.name, files, lastChangeMs, now))
    }
  }

  efforts.sort((a, b) => rank(a) - rank(b) || b.lastChangeMs - a.lastChangeMs)

  return { root, scannedAt: now, efforts }
}

export function summary(board: ScratchBoard): string {
  if (board.efforts.length === 0) {
    return 'No efforts in .scratch/.'
  }
  const count = (fn: (e: ScratchEffort) => boolean) => board.efforts.filter(fn).length
  const rows = board.efforts.map(e => {
    const open = e.files.filter(f => !isClosed(f)).map(f => f.number || f.path).join(', ')
    return `| \`${e.slug}\` | ${e.state}${e.isStale ? ' (stale)' : ''} | ${open} | ${e.next} |`
  })

  return [
    '| Effort | State | Open | Next |',
    '|---|---|---|---|',
    ...rows,
    '',
    `${count(e => e.state === 'open')} open, ${count(e => e.isStale)} stale, ` +
      `${count(e => e.state === 'mismatched')} mismatched, ${count(e => e.state === 'done')} done. ` +
      'Commit checks: /scratch-status.',
  ].join('\n')
}
