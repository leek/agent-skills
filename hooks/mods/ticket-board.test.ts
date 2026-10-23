import { describe, expect, test } from 'claude-code/testing'

import { apply, parseUpdate, summary, tally } from './ticket-board'

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
})

describe('parseUpdate', () => {
  test('a stage-only update needs no tickets', async () => {
    const result = parseUpdate({ board: 'auth', kind: 'spec', stage: 'final checks' })
    expect(result).toEqual({ board: 'auth', kind: 'spec', tickets: [], stage: 'final checks', findings: [] })
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
