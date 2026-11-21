import { expect, test } from 'claude-code/testing'

import type { Worker } from '../../types'
import { duration, ordered, trimWorkers, workerKey } from './workers-model'

const worker = (id: string, outcome: Worker['outcome'] = 'running'): Worker => ({
  id,
  name: '',
  type: 'general-purpose',
  description: id,
  startedAt: 0,
  endedAt: outcome === 'running' ? 0 : 1_000,
  tools: 0,
  lastTool: '',
  outcome,
})

test('workerKey takes the name, or else the first word of the description', async () => {
  expect(workerKey({ name: 'auth--01', description: 'build 01' })).toBe('auth--01')
  expect(workerKey({ name: '', description: 'auth--01 build login' })).toBe('auth--01')
  expect(workerKey({ name: '', description: '  auth--fix   round 2' })).toBe('auth--fix')
  expect(workerKey({ name: '', description: '' })).toBe('')
})

test('duration rounds to whole seconds before splitting minutes from seconds and clamps negatives', async () => {
  expect(duration(-5_000)).toBe('0s')
  expect(duration(-1)).toBe('0s')
  expect(duration(0)).toBe('0s')
  expect(duration(59_400)).toBe('59s')
  // Rounding the parts apart printed `60s` and `1m60s` here.
  expect(duration(59_600)).toBe('1m00s')
  expect(duration(60_000)).toBe('1m00s')
  expect(duration(119_700)).toBe('2m00s')
  expect(duration(125_000)).toBe('2m05s')
})

test('ordered returns empty when rows <= 0 so maxRows <= 1 never overflows', async () => {
  const list = [worker('a', 'running'), worker('b', 'answer')]
  expect(ordered(list, 0)).toEqual([])
  expect(ordered(list, -2)).toEqual([])
  expect(ordered(list, 1).map(w => w.id)).toEqual(['a'])
})

test('trimWorkers evicts oldest finished workers before any still running', async () => {
  const list = [
    worker('r1', 'running'),
    worker('d1', 'answer'),
    worker('d2', 'error'),
    worker('r2', 'running'),
    worker('d3', 'answer'),
  ]
  expect(trimWorkers(list, 3).map(w => w.id)).toEqual(['r1', 'r2', 'd3'])
  expect(trimWorkers(list, 2).map(w => w.id)).toEqual(['r1', 'r2'])
  // When more than `limit` workers are still running, oldest running workers drop last.
  const allRunning = [worker('r1', 'running'), worker('r2', 'running'), worker('r3', 'running')]
  expect(trimWorkers(allRunning, 2).map(w => w.id)).toEqual(['r2', 'r3'])
})
