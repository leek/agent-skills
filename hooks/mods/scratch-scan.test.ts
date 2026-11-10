import { describe, expect, test } from 'claude-code/testing'

import { classify, normalizeSlug, parseFile, scan, summary } from './scratch-scan'
import type { Entry, Reader } from './scratch-scan'

const DAY = 86_400_000
const NOW = 100 * DAY

const ticket = (status: string, extra = '') => `---\ntitle: T\nstatus: ${status}\n${extra}---\n\nbody\n`

// An in-memory .scratch/: path → file text; directories are implied by the paths. `mtimes`
// overrides one file's modification time by its full path.
function reader(files: Record<string, string>, mtimeMs = NOW, mtimes: Record<string, number> = {}): Reader {
  return {
    list: async (path: string) => {
      const seen = new Map<string, Entry>()
      for (const full of Object.keys(files)) {
        if (!full.startsWith(`${path}/`)) continue
        const [name, ...rest] = full.slice(path.length + 1).split('/')
        if (name !== undefined) seen.set(name, { name, kind: rest.length > 0 ? 'dir' : 'file', mtimeMs: mtimes[full] ?? mtimeMs })
      }
      return [...seen.values()]
    },
    read: async (path: string) => files[path] ?? '',
  }
}

describe('parseFile', () => {
  test('reads frontmatter fields and both blocked-by spellings', async () => {
    const inline = parseFile('tickets/03-x.md', 'ticket', ticket('ready-for-agent', 'claimed-by: ann-1\nblocked-by: [01, 02]\n'))
    expect(inline.number).toBe('03')
    expect(inline.claimedBy).toBe('ann-1')
    expect(inline.blockedBy).toEqual(['01', '02'])

    const block = parseFile('tickets/03-x.md', 'ticket', ticket('open', 'blocked-by:\n  - 01\n  - 02\n'))
    expect(block.blockedBy).toEqual(['01', '02'])
  })

  test('drops an unquoted trailing comment and keeps a quoted #', async () => {
    const file = parseFile(
      'tickets/02-x.md',
      'ticket',
      '---\ntitle: "Fix #12" # note\nstatus: closed # shipped\nclaimed-by: # nobody\nblocked-by: [01] # see [09]\n---\n',
    )
    expect(file.title).toBe('Fix #12')
    expect(file.status).toBe('closed')
    expect(file.claimedBy).toBe('')
    expect(file.blockedBy).toEqual(['01'])
  })

  test('falls back to a legacy Status line', async () => {
    expect(parseFile('req.md', 'request', '# Bug\n\n**Status:** needs-triage\n').status).toBe('needs-triage')
  })
})

describe('classify', () => {
  test('frontier skips blocked and claimed tickets, next names the first ready one', async () => {
    const files = [
      parseFile('spec.md', 'spec', ticket('ready-for-agent')),
      parseFile('tickets/01-a.md', 'ticket', ticket('closed')),
      parseFile('tickets/02-b.md', 'ticket', ticket('ready-for-agent', 'blocked-by: [01]\n')),
      parseFile('tickets/03-c.md', 'ticket', ticket('ready-for-agent', 'blocked-by: [02]\n')),
      parseFile('tickets/04-d.md', 'ticket', ticket('in-progress', 'claimed-by: bo-2\n')),
    ]
    const effort = classify('auth', files, NOW, NOW)
    expect(effort.state).toBe('open')
    expect(effort.frontier).toEqual(['tickets/02-b.md'])
    expect(effort.next).toBe('/implement .scratch/auth/tickets/02-b.md')
  })

  test('a delivery ticket at ready-for-human waits for the deploy', async () => {
    const files = [
      parseFile('spec.md', 'spec', ticket('ready-for-agent')),
      parseFile('tickets/01-a.md', 'ticket', ticket('closed')),
      parseFile('tickets/02-delivery.md', 'ticket', ticket('ready-for-human', 'blocked-by: [01]\ndelivery: true\n')),
    ]
    expect(classify('auth', files, NOW, NOW).next).toBe('after deploy: /implement .scratch/auth/tickets/02-delivery.md')
  })

  test('a spec is complete once every ticket is closed; a spec with no tickets needs its own closed status', async () => {
    const closed = [parseFile('tickets/01-a.md', 'ticket', ticket('closed'))]
    expect(classify('x', closed, NOW, NOW).state).toBe('done')

    // Nothing writes `closed` onto a spec built through tickets, so its own status is not asked.
    const built = classify('x', [parseFile('spec.md', 'spec', ticket('ready-for-agent')), ...closed], NOW, NOW)
    expect(built.state).toBe('done')
    expect(built.next).toBe('/scratch-cleanup')

    const direct = classify('x', [parseFile('spec.md', 'spec', ticket('ready-for-agent'))], NOW, NOW)
    expect(direct.state).toBe('open')
    expect(direct.next).toBe('/to-tickets .scratch/x/spec.md')
    expect(classify('x', [parseFile('spec.md', 'spec', ticket('closed'))], NOW, NOW).state).toBe('done')
  })

  test('an open map with every decision closed and no spec points /to-spec at the map', async () => {
    const files = [parseFile('map.md', 'map', ticket('open')), parseFile('decisions/01-q.md', 'decision', ticket('closed'))]
    expect(classify('m', files, NOW, NOW).next).toBe('/to-spec .scratch/m/map.md')
  })

  test('stale after 30 days without a change', async () => {
    const files = [parseFile('decisions/01-q.md', 'decision', ticket('open'))]
    expect(classify('m', files, NOW - 31 * DAY, NOW).isStale).toBe(true)
    expect(classify('m', files, NOW - 29 * DAY, NOW).isStale).toBe(false)
  })
})

test('scan finds efforts, skips research/ and status-less notes, ranks ready work first', async () => {
  const fs = reader({
    '/r/.scratch/research/notes.md': '# notes',
    '/r/.scratch/done/tickets/01-a.md': ticket('closed'),
    '/r/.scratch/live/spec.md': ticket('ready-for-agent'),
    '/r/.scratch/live/scribble.md': 'just a note',
    '/r/.scratch/live/tickets/01-a.md': ticket('ready-for-agent'),
  })
  const board = await scan(fs, '/r/.scratch', NOW)
  expect(board.efforts.map(e => e.slug)).toEqual(['live', 'done'])
  expect(board.efforts[0]?.files.map(f => f.path).sort()).toEqual(['spec.md', 'tickets/01-a.md'])
  expect(summary(board)).toContain('1 open, 0 stale, 0 mismatched, 1 done')

  const one = await scan(fs, '/r/.scratch', NOW, 'done')
  expect(one.efforts.map(e => e.slug)).toEqual(['done'])
})

test('scan counts every closed word, and the repo\'s custom wontfix string, as closed', async () => {
  const fs = reader({
    '/r/.agents/triage-labels.md': '| Role | Status | Meaning |\n| `wontfix` | `not-planned` | Will not be actioned |\n',
    '/r/.scratch/a/tickets/01-a.md': ticket('done'),
    '/r/.scratch/a/tickets/02-b.md': ticket('resolved'),
    '/r/.scratch/a/tickets/03-c.md': ticket('duplicate'),
    '/r/.scratch/a/tickets/04-d.md': ticket('declined'),
    '/r/.scratch/a/tickets/05-e.md': ticket('not-planned'),
  })
  const board = await scan(fs, '/r/.scratch', NOW)
  expect(board.efforts[0]?.state).toBe('done')
})

// The cases where the board once disagreed with skills/scratch-status/scripts/scratch-state.sh.
// Each expected row is what scratch-state.sh printed for the same files on disk (`oldcommit`
// committed 40 days before the run, `oldnote`'s ticket modified 40 days before it, the rest
// new and untracked): change a row only by running the script again.
const md = (status: string, extra = '', body = 'body\n') => `---\ntitle: T\nstatus: ${status}\n${extra}---\n\n${body}`

const SHARED: Record<string, string> = {
  // Finding 1: quoted block items, digit extraction, none / ~ as no blockers, quoted bare value.
  'quotes/spec.md': md('ready-for-agent'),
  'quotes/tickets/01-a.md': md('closed'),
  'quotes/tickets/02-b.md': md('ready-for-agent', 'blocked-by:\n  - "01"\n'),
  'quotes/tickets/03-c.md': md('ready-for-agent', 'blocked-by: [02-b]\n'),
  'quotes/tickets/04-d.md': md('ready-for-agent', 'blocked-by: none\n'),
  'quotes/tickets/05-e.md': md('ready-for-agent', 'blocked-by: ~\n'),
  'quotes/tickets/06-f.md': md('ready-for-agent', "blocked-by: '2'\n"),
  // Finding 2: in-progress with no claim is not on the frontier.
  'inprog/tickets/01-a.md': md('in-progress'),
  // Finding 3: legacy body lines.
  'legacy/tickets/01-a.md': '# One\n\n**Status:** ready-for-agent\n**Claimed by:** ann-1\n',
  'legacy/tickets/02-b.md': '# Two\n\n**Status:** ready-for-agent\n**Blocked by:** 01, 03\n',
  'legacy/tickets/03-c.md': '# Three\n\n**Status:** closed\n',
  'legacy/tickets/04-d.md': '# Four\n\nStatus: ready-for-agent\nBlocked by: none\nClaimed by: none\n',
  // The lowest-numbered ready ticket goes first, however many tickets another one unblocks.
  'unblock/spec.md': md('ready-for-agent'),
  'unblock/tickets/01-a.md': md('ready-for-agent'),
  'unblock/tickets/02-b.md': md('ready-for-agent'),
  'unblock/tickets/03-c.md': md('ready-for-agent', 'blocked-by: [02]\n'),
  'unblock/tickets/04-d.md': md('ready-for-agent', 'blocked-by: [02]\n'),
  // An unquoted trailing ` # comment` is not part of a value; a quoted value keeps its `#`.
  'comments/tickets/01-a.md': md('closed # shipped'),
  'comments/tickets/02-b.md': md('ready-for-agent', 'claimed-by: ann-1 # since Monday\n'),
  'comments/tickets/03-c.md': md('ready-for-agent', 'claimed-by: # nobody\nblocked-by: [01] # see [02]\n'),
  'comments/tickets/04-d.md': md('ready-for-agent', 'blocked-by: 02 # waits\n'),
  'comments/tickets/05-e.md': md('ready-for-agent', 'blocked-by:\n  - 02 # waits\n'),
  // Lowest number first is numeric: 9 before 10.
  'numeric/tickets/10-j.md': md('ready-for-agent'),
  'numeric/tickets/9-i.md': md('ready-for-agent'),
  // Finding 4: open questions and no ticket started.
  'questions/spec.md': md('ready-for-agent', '', '## Open Questions\n\n- Which queue?\n\n## Notes\n\nx\n'),
  'questions/tickets/01-a.md': md('ready-for-agent'),
  // Finding 4: a waiting delivery ticket does not outrank a buildable one.
  'delivery/spec.md': md('ready-for-agent'),
  'delivery/tickets/01-ship.md': md('ready-for-human', 'delivery: true\n'),
  'delivery/tickets/02-b.md': md('ready-for-agent'),
  // Finding 4: an open map with no decisions comes before /triage.
  'mapreq/map.md': md('open'),
  'mapreq/bug.md': md('needs-triage'),
  // Decision B: a spec with tickets is closed by derivation; a spec without is not.
  'derived/map.md': md('closed'),
  'derived/spec.md': md('ready-for-agent'),
  'derived/tickets/01-a.md': md('closed'),
  'direct/spec.md': md('ready-for-agent'),
  'directdone/spec.md': md('closed'),
  // Decision C: wayfinder and to-spec take the map.
  'wayf/map.md': md('open'),
  'wayf/decisions/01-q.md': md('open'),
  'wayf/decisions/02-r.md': md('open', 'blocked-by: [01]\n'),
  'tospec/map.md': md('open'),
  'tospec/decisions/01-q.md': md('closed'),
  // Finding 5: a tracked file's age is its last commit; a dropped note's age does not count.
  'oldcommit/tickets/01-a.md': md('ready-for-agent'),
  'oldnote/tickets/01-a.md': md('ready-for-agent'),
  'oldnote/scribble.md': 'just a note\n',
}

const FROM_SCRATCH_STATE: Record<string, { state: string; stale: boolean; frontier: string[]; next: string }> = {
  quotes: {
    state: 'open',
    stale: false,
    frontier: ['tickets/02-b.md', 'tickets/04-d.md', 'tickets/05-e.md'],
    next: '/implement .scratch/quotes/tickets/02-b.md',
  },
  inprog: { state: 'open', stale: false, frontier: [], next: 'everything open is blocked' },
  legacy: { state: 'open', stale: false, frontier: ['tickets/04-d.md'], next: '/implement .scratch/legacy/tickets/04-d.md' },
  unblock: {
    state: 'open',
    stale: false,
    frontier: ['tickets/01-a.md', 'tickets/02-b.md'],
    next: '/implement .scratch/unblock/tickets/01-a.md',
  },
  comments: { state: 'open', stale: false, frontier: ['tickets/03-c.md'], next: '/implement .scratch/comments/tickets/03-c.md' },
  numeric: {
    state: 'open',
    stale: false,
    frontier: ['tickets/9-i.md', 'tickets/10-j.md'],
    next: '/implement .scratch/numeric/tickets/9-i.md',
  },
  questions: { state: 'open', stale: false, frontier: ['tickets/01-a.md'], next: '/grill-me .scratch/questions/spec.md' },
  delivery: {
    state: 'open',
    stale: false,
    frontier: ['tickets/01-ship.md', 'tickets/02-b.md'],
    next: '/implement .scratch/delivery/tickets/02-b.md',
  },
  mapreq: { state: 'open', stale: false, frontier: [], next: '/wayfinder .scratch/mapreq/map.md' },
  derived: { state: 'done', stale: false, frontier: [], next: '/scratch-cleanup' },
  direct: { state: 'open', stale: false, frontier: [], next: '/to-tickets .scratch/direct/spec.md' },
  directdone: { state: 'done', stale: false, frontier: [], next: '/scratch-cleanup' },
  wayf: { state: 'open', stale: false, frontier: ['decisions/01-q.md'], next: '/wayfinder .scratch/wayf/map.md' },
  tospec: { state: 'open', stale: false, frontier: [], next: '/to-spec .scratch/tospec/map.md' },
  oldcommit: { state: 'open', stale: true, frontier: ['tickets/01-a.md'], next: '/implement .scratch/oldcommit/tickets/01-a.md' },
  oldnote: { state: 'open', stale: true, frontier: ['tickets/01-a.md'], next: '/implement .scratch/oldnote/tickets/01-a.md' },
}

test('scan gives scratch-state.sh\'s state, staleness, frontier, and next on the cases that once differed', async () => {
  const files = Object.fromEntries(Object.entries(SHARED).map(([rel, text]) => [`/r/.scratch/${rel}`, text]))
  const old = NOW - 40 * DAY
  const fs: Reader = {
    ...reader(files, NOW, { '/r/.scratch/oldnote/tickets/01-a.md': old }),
    // Only oldcommit's ticket is tracked: its commit time wins over its fresh mtime.
    commitTimes: async paths => new Map(paths.filter(p => p === '.scratch/oldcommit/tickets/01-a.md').map(p => [p, old])),
  }
  const board = await scan(fs, '/r/.scratch', NOW)
  const got = Object.fromEntries(
    board.efforts.map(e => [e.slug, { state: e.state, stale: e.isStale, frontier: e.frontier, next: e.next }]),
  )
  expect(got).toEqual(FROM_SCRATCH_STATE)
})

test('without commit times a file\'s age is its mtime, and a failing lookup falls back the same way', async () => {
  const files = { '/r/.scratch/a/tickets/01-a.md': ticket('open') }
  const old = reader(files, NOW - 40 * DAY)
  expect((await scan(old, '/r/.scratch', NOW)).efforts[0]?.isStale).toBe(true)

  const broken: Reader = { ...old, commitTimes: async () => Promise.reject(new Error('not a git repository')) }
  expect((await scan(broken, '/r/.scratch', NOW)).efforts[0]?.isStale).toBe(true)
})

test('an unreadable file or a directory gone mid-scan does not reject the scan', async () => {
  const base = reader({
    '/r/.scratch/ok/tickets/01-a.md': ticket('open'),
    '/r/.scratch/torn/spec.md': ticket('ready-for-agent'),
    '/r/.scratch/torn/note.md': ticket('needs-triage'),
    '/r/.scratch/torn/tickets/01-a.md': ticket('open'),
    '/r/.scratch/gone/tickets/01-a.md': ticket('open'),
  })
  const fs: Reader = {
    list: async path => {
      if (path === '/r/.scratch/gone' || path === '/r/.scratch/torn/tickets') throw new Error('ENOENT')
      return base.list(path)
    },
    read: async path => {
      if (path.startsWith('/r/.scratch/torn/')) throw new Error('EACCES')
      return base.read(path)
    },
  }
  const board = await scan(fs, '/r/.scratch', NOW)
  // `gone` lists nothing, so it is no effort; `torn`'s loose note reads as status-less and is
  // dropped; its spec has no readable status, which is a mismatch, as scratch-state.sh reports.
  expect(board.efforts.map(e => [e.slug, e.state, e.next])).toEqual([
    ['ok', 'open', '/implement .scratch/ok/tickets/01-a.md'],
    ['torn', 'mismatched', 'no readable status: spec.md'],
  ])

  const noRoot: Reader = { list: async () => Promise.reject(new Error('ENOENT')), read: base.read }
  expect((await scan(noRoot, '/r/.scratch', NOW)).efforts).toEqual([])
})

test('normalizeSlug reads a path or a slash-wrapped slug as the slug', async () => {
  expect(normalizeSlug(' auth ')).toBe('auth')
  expect(normalizeSlug('.scratch/auth/')).toBe('auth')
  expect(normalizeSlug('/auth/')).toBe('auth')
  expect(normalizeSlug('')).toBe('')
})
