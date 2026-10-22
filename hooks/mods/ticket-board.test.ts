import { describe, expect, test } from 'claude-code/testing'

import { apply, parseUpdate, tally } from './ticket-board'

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
  test('refuses an unknown status with the allowed list', async () => {
    const result = parseUpdate({ board: 'auth', kind: 'spec', tickets: [{ number: '01', status: 'done' }] })
    expect(typeof result === 'string' && result.includes('resolved')).toBe(true)
  })
})
