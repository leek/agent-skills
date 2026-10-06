import { describe, expect, test } from 'claude-code/testing'

import { classify, parseFile, scan, summary } from './scratch-scan'
import type { Entry, Reader } from './scratch-scan'

const DAY = 86_400_000
const NOW = 100 * DAY

const ticket = (status: string, extra = '') => `---\ntitle: T\nstatus: ${status}\n${extra}---\n\nbody\n`

// An in-memory .scratch/: path → file text; directories are implied by the paths.
function reader(files: Record<string, string>, mtimeMs = NOW): Reader {
  return {
    list: async (path: string) => {
      const seen = new Map<string, Entry>()
      for (const full of Object.keys(files)) {
        if (!full.startsWith(`${path}/`)) continue
        const [name, ...rest] = full.slice(path.length + 1).split('/')
        if (name !== undefined) seen.set(name, { name, kind: rest.length > 0 ? 'dir' : 'file', mtimeMs })
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

  test('all closed is done; an open spec over closed tickets is mismatched', async () => {
    const closed = [parseFile('tickets/01-a.md', 'ticket', ticket('closed'))]
    expect(classify('x', closed, NOW, NOW).state).toBe('done')

    const stuck = [parseFile('spec.md', 'spec', ticket('ready-for-agent')), ...closed]
    const effort = classify('x', stuck, NOW, NOW)
    expect(effort.state).toBe('mismatched')
    expect(effort.next).toBe('spec still ready-for-agent while every ticket is closed')
  })

  test('an open map with every decision closed and no spec points at /to-spec', async () => {
    const files = [parseFile('map.md', 'map', ticket('open')), parseFile('decisions/01-q.md', 'decision', ticket('closed'))]
    expect(classify('m', files, NOW, NOW).next).toBe('/to-spec')
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
