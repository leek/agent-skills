import { describe, expect, test } from 'claude-code/testing'

import { apply, header, isUntracked, openMark, parseUpdate, summary, tally, ticketColor, ticketMark } from './ticket-board'

describe('apply', () => {
  test('first update lists the tickets; later ones change status by number and keep titles', async () => {
    const first = apply(null, {
      board: 'auth',
      kind: 'spec',
      tickets: [
        { number: '02', title: 'Logout', status: 'blocked', note: 'by 01' },
        { number: '01', title: 'Login', status: 'running' },
      ],
    }, 1)
    expect(first.tickets.map(t => t.number)).toEqual(['01', '02'])

    const second = apply(first, {
      board: 'auth',
      kind: 'spec',
      tickets: [{ number: '01', status: 'merged', note: 'abc123' }, { number: '02', status: 'ready' }],
    }, 2)
    expect(second.tickets[0]).toEqual({ number: '01', title: 'Login', status: 'merged', note: 'abc123' })
    // A status change drops the note that explained the old status.
    expect(second.tickets[1]?.note).toBe('')
    expect(tally(second)).toBe('1 of 2 done · 1 ready')
  })

  test('a delivery ticket waiting on deploy is not done', async () => {
    const board = apply(null, {
      board: 'auth',
      kind: 'spec',
      tickets: [
        { number: '01', title: 'Login', status: 'closed' },
        { number: '02', title: 'Delivery check', status: 'awaiting-deploy', note: 'migrate, backfill' },
      ],
    }, 1)
    expect(tally(board)).toBe('1 of 2 done · 1 awaiting-deploy')
  })

  test('a different slug or kind starts a new board', async () => {
    const auth = apply(null, { board: 'auth', kind: 'spec', tickets: [{ number: '01', title: 'Login', status: 'running' }] }, 1)
    const map = apply(auth, { board: 'auth', kind: 'map', tickets: [{ number: '01', title: 'Which IdP?', status: 'ready' }] }, 2)
    expect(map.tickets).toEqual([{ number: '01', title: 'Which IdP?', status: 'ready', note: '' }])
  })

  test('after the build, the stage and findings update without touching the tickets', async () => {
    const built = apply(null, { board: 'auth', kind: 'spec', tickets: [{ number: '01', title: 'Login', status: 'merged' }], findings: [] }, 1)
    const review = apply(built, {
      board: 'auth',
      kind: 'spec',
      tickets: [],
      stage: 'fix pass',
      findings: [
        { id: '1', title: 'Old workers\' runs vanish from the audit list', status: 'fixing' },
        { id: '0', title: 'Idle keepalives can use up every worker', status: 'open' },
      ],
    }, 2)
    const fixed = apply(review, { board: 'auth', kind: 'spec', tickets: [], findings: [{ id: '1', status: 'fixed', note: 'a1b2c3' }] }, 3)
    expect(fixed.tickets).toEqual(built.tickets)
    expect(fixed.stage).toBe('fix pass')
    // The review's order stands; ids are not sorted.
    expect(fixed.findings.map(f => f.id)).toEqual(['1', '0'])
    expect(fixed.findings[0]).toEqual({ id: '1', title: "Old workers' runs vanish from the audit list", status: 'fixed', note: 'a1b2c3' })
    expect(summary(fixed)).toBe('1 of 1 done · fix pass · 1 of 2 fixed · 1 open')
  })

  test('a map run adds tickets as answers surface them; skipped tickets leave the count', async () => {
    const map = apply(null, {
      board: 'billing',
      kind: 'map',
      tickets: [
        { number: '01', title: 'Proration', status: 'resolved' },
        { number: '02', title: 'Old plans', status: 'skipped', note: 'claimed by ann' },
      ],
    }, 1)
    const grown = apply(map, { board: 'billing', kind: 'map', tickets: [{ number: '03', title: 'Refund window', status: 'ready' }] }, 2)
    expect(tally(grown)).toBe('1 of 2 done · 1 ready')
  })

  test('not-built and released tickets stay in the total; only skipped ones leave it', async () => {
    const board = apply(null, {
      board: 'auth',
      kind: 'spec',
      tickets: [
        { number: '01', title: 'Login', status: 'closed' },
        { number: '02', title: 'Logout', status: 'not-built', note: 'held for a person' },
        { number: '03', title: 'Reset', status: 'not-built', note: 'claimed by ann' },
        { number: '04', title: 'SSO', status: 'released', note: 'schema question' },
        { number: '05', title: 'Old flow', status: 'skipped', note: 'closed in an earlier run' },
      ],
    }, 1)
    expect(tally(board)).toBe('1 of 4 done · 2 not built · 1 released')
    expect(ticketMark('not-built')).not.toBe(ticketMark('skipped'))
    expect(ticketMark('not-built')).not.toBe(ticketMark('closed'))
    expect(ticketColor('not-built')).toBe('warning')
    expect(ticketColor('skipped')).toBeUndefined()
  })

  test('the open list upserts by id, marks an entry with no tracking place, and strikes a done one', async () => {
    const built = apply(null, {
      board: 'auth',
      kind: 'spec',
      tickets: [{ number: '01', title: 'Login', status: 'closed' }],
      open: [
        { id: 'a', title: 'Fix for the audit list is not pushed', kind: 'not-shipped', where: '#101' },
        { id: 'b', title: 'Second sign-in method', kind: 'your-decision' },
        { id: 'c', title: 'Checkout was never opened in a browser', kind: 'not-verified', where: ' Untracked ' },
      ],
    }, 1)
    expect(built.open.map(o => o.where)).toEqual(['#101', 'untracked', 'Untracked'])
    expect(built.open.map(isUntracked)).toEqual([false, true, true])
    expect(openMark(built.open[1]!)).toBe('!')
    expect(header(built)).toBe('1 of 1 done · 3 open after this run (2 untracked)')

    const later = apply(built, {
      board: 'auth',
      kind: 'spec',
      tickets: [],
      open: [
        { id: 'a', kind: 'not-shipped', done: true },
        { id: 'b', kind: 'your-decision', where: '.scratch/auth/decisions/02-second-sign-in.md' },
      ],
    }, 2)
    // The order the run listed them in stands, and an update keeps the title.
    expect(later.open.map(o => o.id)).toEqual(['a', 'b', 'c'])
    expect(later.open[0]).toEqual({ id: 'a', title: 'Fix for the audit list is not pushed', kind: 'not-shipped', where: '#101', done: true })
    expect(openMark(later.open[0]!)).toBe('✓')
    expect(isUntracked(later.open[1]!)).toBe(false)
    expect(summary(later)).toBe('1 of 1 done · 2 open after this run (1 untracked)')
  })

  test('a call with only the old fields reads as before: no open list, no open count', async () => {
    const board = apply(null, { board: 'auth', kind: 'spec', tickets: [{ number: '01', title: 'Login', status: 'merged' }] }, 1)
    expect(board.open).toEqual([])
    expect(header(board)).toBe('1 of 1 done')
    expect(summary(board)).toBe('1 of 1 done')
  })
})

describe('parseUpdate', () => {
  test('a stage-only update needs no tickets', async () => {
    const result = parseUpdate({ board: 'auth', kind: 'spec', stage: 'final checks' })
    expect(result).toEqual({ board: 'auth', kind: 'spec', tickets: [], stage: 'final checks', findings: [], open: [] })
  })

  test('refuses an open entry with an unknown kind', async () => {
    const result = parseUpdate({ board: 'auth', kind: 'spec', open: [{ id: 'a', kind: 'todo' }] })
    expect(typeof result === 'string' && result.includes('your-decision')).toBe(true)
  })

  test('refuses a finding with an unknown status', async () => {
    const result = parseUpdate({ board: 'auth', kind: 'spec', findings: [{ id: '1', status: 'done' }] })
    expect(typeof result === 'string' && result.includes('deferred')).toBe(true)
  })

  test('refuses an unknown status with the allowed list', async () => {
    const result = parseUpdate({ board: 'auth', kind: 'spec', tickets: [{ number: '01', status: 'done' }] })
    expect(typeof result === 'string' && result.includes('resolved')).toBe(true)
  })
})
