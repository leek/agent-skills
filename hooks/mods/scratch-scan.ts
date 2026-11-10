// Reads .scratch/ into a board: the deterministic half of the scratch-status skill.
// A port of skills/scratch-status/scripts/scratch-state.sh: the same state, frontier, and
// `next` on every case, and the same last-change time when the reader supplies commit times.
// Skill-only, never checked here: whether a closed ticket's cited commits are on the default
// branch (a `mismatched` cause the board cannot see), and the `also` alternatives.

import type { ScratchBoard, ScratchEffort, ScratchFile, ScratchKind } from '../../types'

export type Entry = { name: string; kind: 'file' | 'dir' | 'other'; mtimeMs: number }

export type Reader = {
  list: (path: string) => Promise<readonly Entry[]>
  read: (path: string) => Promise<string>
  /**
   * Last commit time in ms of each git-tracked path, keyed by the path given
   * (`.scratch/<slug>/<file>`, relative to the repository). A path left out is untracked or
   * unknown and falls back to its mtime, as scratch-state.sh does. Absent: mtimes only.
   */
  commitTimes?: (paths: readonly string[]) => Promise<ReadonlyMap<string, number>>
}

// Mirrors load_closed_vocabulary in skills/scratch-status/scripts/scratch-state.sh.
const WONTFIX = ['wontfix', 'declined', 'duplicate']
const CLOSED = new Set(['closed', 'done', 'resolved', ...WONTFIX])
const STALE_MS = 30 * 24 * 60 * 60 * 1000
const TICKET_DIRS: Record<string, ScratchKind> = {
  decisions: 'decision',
  tickets: 'ticket',
  issues: 'ticket',
}
const NO_VALUE = ['none', 'null', '-']

export const isClosed = (file: ScratchFile) => CLOSED.has(file.status)

// Code-point order, as Python sorts strings; localeCompare would order by locale.
const byText = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0)

const unquote = (s: string) => s.replace(/^["']+|["']+$/g, '')

const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

/** `/scratch`'s argument as a slug: `.scratch/auth/`, `/auth/`, and `auth` all name `auth`. */
export function normalizeSlug(arg: string): string {
  const slug = arg.trim().replace(/^\/+|\/+$/g, '')

  return slug.startsWith('.scratch/') ? slug.slice('.scratch/'.length).replace(/^\/+|\/+$/g, '') : slug
}

function section(body: string, heading: string): string {
  const match = body.match(new RegExp(`^##\\s+(?:${heading})\\s*$([\\s\\S]*?)(?=^##\\s+|(?![\\s\\S]))`, 'mi'))

  return match?.[1]?.trim() ?? ''
}

// A blocker id is the first run of digits in the token: `01-login` and `[01-a]` both mean 01.
const blockerId = (token: string) => token.match(/\d+/)?.[0] ?? token.trim()

export function parseFile(path: string, kind: ScratchKind, text: string): ScratchFile {
  const name = path.split('/').pop() ?? path
  const number = kind === 'decision' || kind === 'ticket' ? (name.match(/^(\d+)/)?.[1] ?? '') : ''
  const split = text.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/)
  const front = split?.[1] ?? ''
  const body = split ? (split[2] ?? '') : text
  const field = (key: string) => unquote(front.match(new RegExp(`^${escape(key)}:[ \\t]*(.*)$`, 'm'))?.[1]?.trim() ?? '')

  let status = field('status')
  if (status === '') {
    const head = text.split(/\r?\n/).slice(0, 30).join('\n')
    status = (head.match(/^\*\*Status:\*\*\s*(.+)$/m)?.[1] ?? head.match(/^Status:\s*(.+)$/m)?.[1] ?? '').trim()
  }

  // Older files carry the claim and the blockers as body lines, not frontmatter.
  let claimedBy = field('claimed-by')
  if (claimedBy === '') {
    const legacy = body.match(/^(?:\*\*Claimed by:\*\*|Claimed by:)\s*(.+)$/im)?.[1]?.trim() ?? ''
    claimedBy = NO_VALUE.includes(legacy.toLowerCase()) ? '' : legacy
  }
  let blockedBy = parseList(front, 'blocked-by').map(blockerId)
  if (blockedBy.length === 0) {
    const legacy = body.match(/^(?:\*\*Blocked by:\*\*|Blocked by:)\s*(.+)$/im)?.[1]?.trim() ?? ''
    blockedBy = NO_VALUE.includes(legacy.toLowerCase()) ? [] : (legacy.match(/\b\d+\b/g) ?? [])
  }

  const questions =
    kind === 'spec'
      ? section(body, 'Open Questions')
          .split(/\r?\n/)
          .map(line => line.trim())
          .filter(line => line !== '' && !/^[-*]*\s*(?:none\.?|n\/a)\s*$/i.test(line))
      : []

  return {
    path,
    kind,
    number,
    title: field('title') || body.match(/^#\s+(.+)$/m)?.[1]?.trim() || name.replace(/\.md$/, ''),
    status: (status.trim().replace(/[`*]/g, '').trim().split(/\s+/)[0] ?? '').toLowerCase(),
    claimedBy,
    blockedBy,
    delivery: field('delivery').toLowerCase() === 'true',
    openQuestions: questions.length,
  }
}

function parseList(front: string, key: string): string[] {
  const name = escape(key)
  const items = (raw: string) => raw.split(',').map(s => unquote(s.trim())).filter(Boolean)
  const inline = front.match(new RegExp(`^${name}:[ \\t]*\\[(.*)\\]`, 'm'))
  if (inline) {
    return items(inline[1] ?? '')
  }
  const block = front.match(new RegExp(`^${name}:[ \\t]*\\r?\\n((?:[ \\t]*-.*\\r?\\n?)+)`, 'm'))
  if (block) {
    return (block[1] ?? '')
      .split(/\r?\n/)
      .map(line => line.replace(/^\s*-\s*/, '').trim())
      .filter(Boolean)
      .map(unquote)
  }
  const bare = front.match(new RegExp(`^${name}:[ \\t]*(\\S.*)$`, 'm'))?.[1]?.trim() ?? ''

  return ['none', 'null', '~', '[]'].includes(bare.toLowerCase()) ? [] : items(bare)
}

type Derived = 'unreadable' | 'closed' | 'in progress' | 'blocked' | 'ready'

/**
 * The files that still keep an effort open. A spec built through tickets is complete when
 * every ticket is closed: nothing writes `closed` onto it, so its own status is not asked.
 * A spec with no tickets was implemented directly and needs its own closed status.
 */
export function openFiles(files: readonly ScratchFile[]): ScratchFile[] {
  const tickets = files.filter(f => f.kind === 'ticket')
  const isSpecComplete = tickets.length > 0 && tickets.every(isClosed)

  return files.filter(f => !isClosed(f) && !(f.kind === 'spec' && isSpecComplete))
}

export function classify(slug: string, files: ScratchFile[], lastChangeMs: number, now: number): ScratchEffort {
  const at = (path: string) => `.scratch/${slug}/${path}`
  const byKind = (kind: ScratchKind) => files.filter(f => f.kind === kind)
  const isWork = (file: ScratchFile) => file.kind === 'decision' || file.kind === 'ticket'

  // Each open decision or ticket's blockers that are not closed, zero-padded to its own width.
  const openBlockers = (file: ScratchFile) =>
    !isWork(file) || isClosed(file) || file.status === ''
      ? []
      : file.blockedBy.flatMap(raw => {
          const id = /^\d+$/.test(raw) ? raw.padStart(file.number.length || 2, '0') : raw
          const blocker = files.find(f => f.kind === file.kind && (f.number === id || f.number === raw))

          return blocker === undefined || !isClosed(blocker) ? [id] : []
        })
  const blockers = new Map(files.map(f => [f, openBlockers(f)]))
  const derived = (file: ScratchFile): Derived => {
    if (file.status === '') return 'unreadable'
    if (isClosed(file)) return 'closed'
    if (file.claimedBy !== '' || file.status === 'in-progress') return 'in progress'

    return (blockers.get(file) ?? []).length > 0 ? 'blocked' : 'ready'
  }
  const isReady = (file: ScratchFile) => derived(file) === 'ready'

  const frontier = files
    .filter(f => isWork(f) && isReady(f))
    .sort((a, b) => byText(a.number, b.number))
    .map(f => f.path)

  const base = { slug, files, lastChangeMs, frontier, isStale: false }
  const mismatch = findMismatch(files)
  if (mismatch !== '') {
    return { ...base, state: 'mismatched', next: mismatch }
  }
  const open = openFiles(files)
  if (open.length === 0) {
    return { ...base, state: 'done', next: '/scratch-cleanup' }
  }

  const map = byKind('map')[0]
  const spec = byKind('spec')[0]
  const tickets = byKind('ticket')
  const decisions = byKind('decision')
  const isMapOpen = map !== undefined && !isClosed(map)
  const isSpecOpen = spec !== undefined && !isClosed(spec)
  const readyDecision = decisions.find(isReady)
  const isWaitingOnDeploy = (t: ScratchFile) => t.delivery && t.status === 'ready-for-human'
  // How many open tickets each ticket holds back: the most-unblocking ready ticket goes first.
  const unblocks = (t: ScratchFile) =>
    tickets.filter(other => !isClosed(other) && (blockers.get(other) ?? []).includes(t.number)).length
  const buildable = tickets
    .filter(t => isReady(t) && !isWaitingOnDeploy(t))
    .sort((a, b) => unblocks(b) - unblocks(a) || byText(a.number, b.number))
  const waiting = tickets.find(t => isReady(t) && isWaitingOnDeploy(t))

  // The same order as scratch-state.sh's `next` chain; change both together.
  let next = ''
  if (readyDecision) {
    // An open map's decisions are worked through wayfinder, which picks the frontier ticket.
    next = isMapOpen ? `/wayfinder ${at(map.path)}` : `/grill-me ${at(readyDecision.path)}`
  } else if (isMapOpen && decisions.length === 0) {
    next = `/wayfinder ${at(map.path)}`
  } else if (isMapOpen && decisions.every(isClosed) && !spec) {
    next = `/to-spec ${at(map.path)}`
  } else if (isSpecOpen && spec.openQuestions > 0 && !tickets.some(t => isClosed(t) || derived(t) === 'in progress')) {
    next = `/grill-me ${at(spec.path)}`
  } else if (isSpecOpen && tickets.length === 0) {
    next = `/to-tickets ${at(spec.path)}`
  } else if (buildable[0]) {
    next = `/implement ${at(buildable[0].path)}`
  } else if (waiting) {
    // The delivery ticket waits at ready-for-human for its after-deploy pass.
    next = `after deploy: /implement ${at(waiting.path)}`
  } else if (byKind('request').some(f => !isClosed(f))) {
    next = '/triage'
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
  const map = files.find(f => f.kind === 'map')
  if (map && !isClosed(map) && files.some(f => f.kind === 'spec')) {
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

// The repo's own wontfix status string, from the setup table row | `wontfix` | `<string>` | … |.
export function wontfixLabels(labelsText: string): string[] {
  return [...labelsText.matchAll(/^\|\s*`wontfix`\s*\|\s*`([^`]+)`/gim)].map(m => (m[1] ?? '').trim().toLowerCase())
}

async function readLabels(fs: Reader, root: string): Promise<string[]> {
  const repo = root.replace(/\/\.scratch\/?$/, '')
  for (const candidate of ['.agents/triage-labels.md', 'docs/agents/triage-labels.md']) {
    try {
      const text = await fs.read(`${repo}/${candidate}`)
      if (text !== '') {
        return wontfixLabels(text)
      }
    } catch {
      // Missing file: try the next location.
    }
  }

  return []
}

// A directory that cannot be listed (removed mid-scan, no permission) reads as empty, and the
// entries come back in name order, the order scratch-state.sh walks them in.
async function listSorted(fs: Reader, path: string): Promise<Entry[]> {
  try {
    return [...(await fs.list(path))].sort((a, b) => byText(a.name, b.name))
  } catch {
    return []
  }
}

// A file that cannot be read has no readable status: a note when loose, a mismatch otherwise.
async function readText(fs: Reader, path: string): Promise<string> {
  try {
    return await fs.read(path)
  } catch {
    return ''
  }
}

export async function scan(fs: Reader, root: string, now: number, only = ''): Promise<ScratchBoard> {
  const efforts: ScratchEffort[] = []
  const customWontfix = new Set((await readLabels(fs, root)).filter(label => !CLOSED.has(label)))
  const dirs = (await listSorted(fs, root)).filter(
    d => d.kind === 'dir' && d.name !== 'research' && !d.name.startsWith('.') && (only === '' || d.name === only),
  )

  for (const dir of dirs) {
    const base = `${root}/${dir.name}`
    const found: { path: string; kind: ScratchKind; mtimeMs: number }[] = []
    for (const entry of await listSorted(fs, base)) {
      if (entry.name.startsWith('.')) {
        continue
      }
      if (entry.kind === 'file' && entry.name.endsWith('.md')) {
        const kind: ScratchKind = entry.name === 'map.md' ? 'map' : entry.name === 'spec.md' ? 'spec' : 'request'
        found.push({ path: entry.name, kind, mtimeMs: entry.mtimeMs })
      } else if (entry.kind === 'dir' && TICKET_DIRS[entry.name] !== undefined) {
        const kind = TICKET_DIRS[entry.name] as ScratchKind
        for (const inner of await listSorted(fs, `${base}/${entry.name}`)) {
          if (inner.kind === 'file' && inner.name.endsWith('.md') && !inner.name.startsWith('.')) {
            found.push({ path: `${entry.name}/${inner.name}`, kind, mtimeMs: inner.mtimeMs })
          }
        }
      }
    }

    const files: ScratchFile[] = []
    const kept: { rel: string; mtimeMs: number }[] = []
    for (const f of found) {
      const parsed = parseFile(f.path, f.kind, await readText(fs, `${base}/${f.path}`))
      if (customWontfix.has(parsed.status)) {
        // The repo's custom wontfix string plays the wontfix role.
        parsed.status = 'wontfix'
      }
      // A loose markdown file with no status is a note, not a triage request: it is dropped,
      // and its age does not count toward the effort's last change.
      if (f.kind !== 'request' || parsed.status !== '') {
        files.push(parsed)
        kept.push({ rel: `.scratch/${dir.name}/${f.path}`, mtimeMs: f.mtimeMs })
      }
    }
    if (files.length > 0) {
      efforts.push(classify(dir.name, files, await lastChange(fs, kept), now))
    }
  }

  efforts.sort((a, b) => rank(a) - rank(b) || b.lastChangeMs - a.lastChangeMs)

  return { root, scannedAt: now, efforts }
}

// The newest kept file: a tracked file's last commit time, an untracked file's mtime.
async function lastChange(fs: Reader, kept: readonly { rel: string; mtimeMs: number }[]): Promise<number> {
  let commits: ReadonlyMap<string, number> = new Map()
  try {
    commits = (await fs.commitTimes?.(kept.map(k => k.rel))) ?? commits
  } catch {
    // No git, or not a repository: mtimes only.
  }

  return Math.max(...kept.map(k => commits.get(k.rel) ?? k.mtimeMs))
}

// One line of counts: the /scratch reply when the pane is drawn.
export function tally(board: ScratchBoard): string {
  if (board.efforts.length === 0) {
    return 'No efforts in .scratch/.'
  }
  const count = (fn: (e: ScratchEffort) => boolean) => board.efforts.filter(fn).length

  return (
    `${count(e => e.state === 'open')} open, ${count(e => e.isStale)} stale, ` +
    `${count(e => e.state === 'mismatched')} mismatched, ${count(e => e.state === 'done')} done. ` +
    'Commit checks: /scratch-status.'
  )
}

// The whole board as a Markdown table: the /scratch reply where no pane is drawn.
export function summary(board: ScratchBoard): string {
  if (board.efforts.length === 0) {
    return 'No efforts in .scratch/.'
  }
  const rows = board.efforts.map(e => {
    const open = openFiles(e.files).map(f => f.number || f.path).join(', ')
    return `| \`${e.slug}\` | ${e.state}${e.isStale ? ' (stale)' : ''} | ${open} | ${e.next} |`
  })

  return [
    '| Effort | State | Open | Next |',
    '|---|---|---|---|',
    ...rows,
    '',
    tally(board),
  ].join('\n')
}
