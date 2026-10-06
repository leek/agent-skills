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
  if (ms < 60_000) {
    return `${Math.round(ms / 1000)}s`
  }

  return `${Math.floor(ms / 60_000)}m${String(Math.round((ms % 60_000) / 1000)).padStart(2, '0')}s`
}

export const isFailed = (w: Worker) => w.outcome === 'error' || w.outcome === 'refusal' || w.outcome === 'aborted'

/** Running first, then failures, then finished, newest first, cut to the rows the band has. */
export function ordered(list: readonly Worker[], rows: number): Worker[] {
  const newest = (fn: (w: Worker) => boolean) => list.filter(fn).reverse()

  return [...list.filter(w => w.outcome === 'running'), ...newest(isFailed), ...newest(w => w.outcome === 'answer')].slice(
    0,
    Math.max(1, rows),
  )
}

export const mark = (w: Worker) =>
  w.outcome === 'running' ? '◐' : w.outcome === 'answer' ? '✓' : w.outcome === 'aborted' ? '◌' : '✗'
