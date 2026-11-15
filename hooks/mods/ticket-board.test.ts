import { describe, expect, test } from 'claude-code/testing'

import {
  apply,
  chainRows,
  chainTokens,
  header,
  isUntracked,
  openMark,
  parseUpdate,
  stackTally,
  stackWarnings,
  summary,
  tally,
  ticketColor,
  ticketMark,
} from './ticket-board'

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
    expect(result).toEqual({ board: 'auth', kind: 'spec', tickets: [], stage: 'final checks', findings: [], open: [], stack: [], integration: undefined })
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

describe('stack', () => {
  const base = { board: 'auth', kind: 'spec' as const, tickets: [] }

  test('the chain reads in landing position, not PR or ticket number, and stops at the first unsafe PR', async () => {
    const board = apply(null, {
      ...base,
      stack: [
        { number: '6488', position: 2, status: 'safe' },
        { number: '6487', position: 1, status: 'safe' },
        { number: '6490', position: 4, status: 'safe' },
        { number: '6489', position: 3, status: 'not-safe', note: 'conflicts with #6488' },
      ],
      integration: { number: '6486', into: 'main', safe: true },
    }, 1)
    expect(chainTokens(board)).toEqual(['#6487', '→ #6488'])
    expect(stackTally(board)).toBe('2 of 4 safe')
    expect(stackWarnings(board)).toEqual(['✗ #6489 not safe · conflicts with #6488', '  waiting behind it: 1 more PR and #6486'])
  })

  test('the integration PR closes the chain only once it is safe; until then it says why', async () => {
    const stack = [
      { number: '6487', position: 1, status: 'safe' as const },
      { number: '6488', position: 2, status: 'safe' as const },
    ]
    const building = apply(null, { ...base, stack, integration: { number: '6486', into: 'main', safe: false, note: 'build not finished' } }, 1)
    expect(chainTokens(building)).toEqual(['#6487', '→ #6488'])
    expect(stackWarnings(building)).toEqual(['✗ integration #6486 into main not safe yet · build not finished'])

    // A later call names only the integration PR; into and the stack carry over, the old note goes.
    const ready = apply(building, { ...base, integration: { number: '6486', safe: true } }, 2)
    expect(chainTokens(ready)).toEqual(['#6487', '→ #6488', '⇒ #6486 into main'])
    expect(stackWarnings(ready)).toEqual([])
    expect(summary(ready)).toContain('stack 2 of 2 safe + integration')
  })

  test('landed PRs leave the chain and are counted; a PR sent with no position goes on top', async () => {
    const first = apply(null, { ...base, stack: [{ number: '101', position: 1, status: 'safe' }, { number: '102', position: 2, status: 'safe' }] }, 1)
    const later = apply(first, { ...base, stack: [{ number: '101', status: 'landed' }, { number: '103', status: 'safe' }] }, 2)
    expect(chainTokens(later)).toEqual(['#102', '→ #103'])
    expect(stackTally(later)).toBe('2 of 2 safe · 1 landed')
  })

  test('a position with no PR yet stops the chain there, and the integration PR waits behind it', async () => {
    const board = apply(null, {
      ...base,
      stack: [
        { number: '101', position: 1, status: 'safe' },
        { number: '103', position: 3, status: 'safe' },
      ],
      integration: { number: '100', into: 'main', safe: true },
    }, 1)
    expect(chainTokens(board)).toEqual(['#101'])
    expect(stackWarnings(board)).toEqual(['✗ position 2 has no open PR yet', '  waiting behind it: 1 more PR and #100'])

    // A landed PR still fills its position.
    const landed = apply(board, { ...base, stack: [{ number: '101', status: 'landed' }, { number: '102', position: 2, status: 'safe' }] }, 2)
    expect(chainTokens(landed)).toEqual(['#102', '→ #103', '⇒ #100 into main'])
  })

  test('rows break only before an arrow and stay inside the width', async () => {
    const tokens = ['#6487', ...Array.from({ length: 20 }, (_, n) => `→ #${6488 + n}`), '⇒ #6486 into main']
    const rows = chainRows(tokens, 40)
    expect(rows.every(r => r.length <= 40)).toBe(true)
    expect(rows.slice(1).every(r => /^[→⇒] #/.test(r))).toBe(true)
    expect(rows.join(' ')).toBe(tokens.join(' '))
  })

  test('parseUpdate refuses a stack entry with no PR number or a bad status', async () => {
    expect(typeof parseUpdate({ ...base, stack: [{ number: 'abc', status: 'safe' }] })).toBe('string')
    expect(typeof parseUpdate({ ...base, stack: [{ number: '1', status: 'green' }] })).toBe('string')
    expect(typeof parseUpdate({ ...base, integration: { number: '1' } })).toBe('string')
    const ok = parseUpdate({ ...base, stack: [{ number: 6487, position: 1, status: 'safe' }] })
    expect(typeof ok === 'string' ? ok : ok.stack).toEqual([{ number: '6487', position: 1, status: 'safe', note: undefined }])
  })
})
