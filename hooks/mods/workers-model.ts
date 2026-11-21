// Pure helpers for the workers band: what a subagent's tool call reads as, and the row order.

import type { Worker } from '../../types'

export const KEEP = 50

export function describeTool(tool: string, input: Record<string, unknown>): string {
  const pick = ['command', 'file_path', 'pattern', 'url', 'query', 'description']
    .map(k => input[k])
    .find(v => typeof v === 'string') as string | undefined
  const short = (pick ?? '').replace(/\s+/g, ' ').trim()

  return short === '' ? tool : `${tool}: ${short}`
}

export function duration(ms: number): string {
  // Round once, to whole seconds, then split: rounding each part alone gives `60s` and `1m60s`.
  const seconds = Math.round(Math.max(0, ms) / 1000)
  if (seconds < 60) {
    return `${seconds}s`
  }

  return `${Math.floor(seconds / 60)}m${String(seconds % 60).padStart(2, '0')}s`
}

/**
 * The key a board run gives a ticket's worker: its `name`, or else the first word of its
 * `description`. Claude Code skills dispatch unnamed (a named sub-agent is never woken by its
 * own background command), so they lead the description with `<slug>--<NN>` instead.
 */
export const workerKey = (w: Pick<Worker, 'name' | 'description'>) => w.name || (w.description ?? '').trim().split(/\s+/)[0] || ''

export const isFailed = (w: Worker) => w.outcome === 'error' || w.outcome === 'refusal' || w.outcome === 'aborted'

/** Running first, then failures, then finished, newest first, cut to the rows the band has. */
export function ordered(list: readonly Worker[], rows: number): Worker[] {
  if (rows <= 0) {
    return []
  }
  const newest = (fn: (w: Worker) => boolean) => list.filter(fn).reverse()

  return [...list.filter(w => w.outcome === 'running'), ...newest(isFailed), ...newest(w => w.outcome === 'answer')].slice(
    0,
    rows,
  )
}

/** Trims to at most `limit` workers, evicting oldest finished workers before any still running. */
export function trimWorkers(list: readonly Worker[], limit = KEEP): Worker[] {
  if (list.length <= limit) {
    return [...list]
  }
  let drop = list.length - limit
  const dropped = new Set<number>()
  for (let i = 0; i < list.length && drop > 0; i++) {
    if (list[i]?.outcome !== 'running') {
      dropped.add(i)
      drop--
    }
  }
  for (let i = 0; i < list.length && drop > 0; i++) {
    if (!dropped.has(i)) {
      dropped.add(i)
      drop--
    }
  }

  return list.filter((_, i) => !dropped.has(i))
}

export const mark = (w: Worker) =>
  w.outcome === 'running' ? '◐' : w.outcome === 'answer' ? '✓' : w.outcome === 'aborted' ? '◌' : '✗'
