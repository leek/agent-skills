// leek-skills' one Claude Code mod module. Each feature is optional polish over a skill
// that already works without it; see AGENTS.md "Mods". Every hook that touches $ lives
// in this file (the engine never follows $ across an import); the imports are pure.
//
// /scratch: a live pane of every .scratch/ effort, opened without a Claude turn. Where
// nothing draws (VS Code chat, claude -p) the command's text reply carries the table.
//
// Workers band: above the prompt, every subagent a fan-out skill dispatched (implement-spec,
// autopilot, browser-test, panel, chatter-scout, code-review), with its tool count, last
// tool, and outcome. Where nothing draws, the skills report their workers as before.

import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { ScratchEffort, Worker } from '../../types'
import { isClosed, scan, summary, tally } from './scratch-scan'
import { KEEP, describeTool, duration, isFailed, mark, ordered } from './workers-model'

const PANE = 'scratch'
const board = atom({ plugin: 'leek-skills', key: 'scratch' } as const, null)
const workers = atom({ plugin: 'leek-skills', key: 'workers' } as const, [])
const isWorkersHidden = atom({ plugin: 'leek-skills', key: 'isWorkersHidden' } as const, false)

const ago = (ms: number) => {
  const days = Math.floor(ms / 86_400_000)
  const hours = Math.floor(ms / 3_600_000)

  return days >= 1 ? `${days}d ago` : hours >= 1 ? `${hours}h ago` : 'just now'
}

// The slug /scratch was last given; empty means every effort.
let only = ''

async function refresh($: EngineInterface) {
  const root = `${await $.session.cwd()}/.scratch`
  if (!(await $.fs.exists(root))) {
    return null
  }
  const reader = { list: (path: string) => $.fs.list(path), read: (path: string) => $.fs.read(path) }
  const result = await scan(reader, root, await $.clock.now(), only)
  await update($, board, () => result)

  return result
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'scratch',
      description: 'Live board of .scratch/ efforts: open tickets, blockers, next step',
      argumentHint: '[effort-slug]',
      immediate: true,
    })

    return next(e)
  })

  on('command.run', { command: 'scratch' }, async ($, e) => {
    only = e.args.trim()
    const result = await refresh($)
    if (result === null) {
      return { text: 'No .scratch/ directory here.' }
    }
    const opened = await $.ui.open({ id: PANE, title: only === '' ? 'Scratch' : `Scratch: ${only}` })

    // The pane carries the board; the text table is only for surfaces that cannot draw it.
    return { text: opened.isPlaced ? tally(result) : summary(result) }
  })

  on('ui.close', { id: PANE }, async ($, e, next) => {
    await update($, board, () => null)

    return next(e)
  }).catch(($, e, next) => next(e))

  // Observe only: count a subagent's tool calls, and rescan the open board after a write
  // under .scratch/. One tool.call hook serves both features.
  on('tool.call', async ($, e, next) => {
    const tool = String(e.tool)
    // A tool's parameters sit on the event itself (e.command, e.file_path), not under an input key.
    const input = e as unknown as Record<string, unknown>
    const id = e.agentId
    if (id !== undefined) {
      const line = describeTool(tool, input)
      await update($, workers, list =>
        list.some(w => w.id === id) ? list.map(w => (w.id === id ? { ...w, tools: w.tools + 1, lastTool: line } : w)) : list,
      )
    }

    const result = await next(e)

    const isScratchWrite =
      tool !== 'Read' && [input.file_path, input.command].some(v => typeof v === 'string' && v.includes('.scratch/'))
    if (isScratchWrite && (await read($, board)) !== null) {
      await refresh($)
    }

    return result
  }).catch(($, e, next) => next(e))

  on('agent.spawn', async ($, e, next) => {
    const result = await next(e)
    if (result.agentId !== undefined) {
      const worker: Worker = {
        id: result.agentId,
        type: e.subagentType,
        description: e.description,
        startedAt: await $.clock.now(),
        endedAt: 0,
        tools: 0,
        lastTool: '',
        outcome: 'running',
      }
      await update($, workers, list => [...list, worker].slice(-KEEP))
      await update($, isWorkersHidden, () => false)
    }

    return result
  }).catch(($, e, next) => next(e))

  on('turn.complete', async ($, e, next) => {
    const id = e.agentId
    if (id !== undefined) {
      const now = await $.clock.now()
      await update($, workers, list => list.map(w => (w.id === id ? { ...w, outcome: e.reason, endedAt: now } : w)))
    }

    return next(e)
  })

  // A new prompt with nothing running starts a clean slate.
  on('prompt.submit', async ($, e, next) => {
    await update($, workers, list => (list.some(w => w.outcome === 'running') ? list : []))

    return next(e)
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const list = await read($, workers)
    if (e.props.hasSurvey || list.length === 0 || (await read($, isWorkersHidden))) {
      return next(e)
    }

    const { Box, Text, Button } = $.ui.resolve(e)
    const now = await $.clock.now()
    const running = list.filter(w => w.outcome === 'running').length
    const failed = list.filter(isFailed).length
    const color = (w: Worker) => (w.outcome === 'running' ? 'suggestion' : w.outcome === 'answer' ? 'success' : 'error')

    return (
      <Box flexDirection="column" width={e.props.bodyColumns}>
        <Box gap={1}>
          <Text bold>
            Workers {list.length - running}/{list.length} done
          </Text>
          {failed > 0 && <Text color="error">{failed} failed</Text>}
          <Button key="hide" label="hide" plain dimColor onPress={() => update($, isWorkersHidden, () => true)} />
        </Box>
        {ordered(list, e.props.maxRows - 1).map(w => (
          <Text key={w.id} wrap="truncate-end">
            <Text color={color(w)}>{mark(w)} </Text>
            <Text>{w.type.replace(/^leek-skills:/, '')}</Text>
            <Text dimColor>
              {'  '}
              {w.description} · {w.tools} tools · {duration((w.endedAt || now) - w.startedAt)}
              {w.outcome === 'running' && w.lastTool !== '' ? ` · ${w.lastTool}` : ''}
            </Text>
          </Text>
        ))}
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const current = await read($, board)
    const now = await $.clock.now()

    const row = (effort: ScratchEffort) => {
      const open = effort.files.filter(f => !isClosed(f))
      const color = effort.state === 'mismatched' ? 'warning' : effort.state === 'done' ? undefined : 'success'
      const sign =
        effort.state === 'done' ? '✓' : effort.state === 'mismatched' ? '!' : effort.frontier.length > 0 ? '●' : '○'
      const work = open.filter(f => f.kind === 'ticket' || f.kind === 'decision')

      return (
        <Box key={effort.slug} flexDirection="column" marginBottom={1}>
          <Text wrap="truncate-end">
            <Text color={color} bold>
              {sign} {effort.slug}
            </Text>
            <Text dimColor>
              {'  '}
              {open.length} open · {effort.files.length - open.length} closed · {ago(now - effort.lastChangeMs)}
            </Text>
            {effort.isStale && <Text color="warning"> · stale</Text>}
          </Text>
          {effort.state === 'open' &&
            work.slice(0, 8).map(f => {
              const isReady = effort.frontier.includes(f.path)
              const tag =
                f.claimedBy !== '' ? `  [${f.claimedBy}]` : !isReady && f.blockedBy.length > 0 ? `  [blocked by ${f.blockedBy.join(', ')}]` : ''

              return (
                <Text key={f.path} wrap="truncate-end" dimColor={!isReady}>
                  {'   '}
                  {f.number} {f.title}
                  {tag}
                </Text>
              )
            })}
          {effort.state === 'open' && work.length > 8 && <Text dimColor>{`   … ${work.length - 8} more`}</Text>}
          <Text wrap="truncate-end" color={effort.state === 'mismatched' ? 'warning' : 'suggestion'}>
            {'   → '}
            {effort.next}
          </Text>
        </Box>
      )
    }

    return (
      <Box flexDirection="column" width={e.props.bodyColumns}>
        <Box gap={1}>
          <Button key="refresh" label="Refresh" hotkey="r" onPress={() => void refresh($)} />
          <Text dimColor>commit checks: /scratch-status</Text>
        </Box>
        {current === null && <Text dimColor>Run /scratch to scan.</Text>}
        {current !== null && current.efforts.length === 0 && <Text dimColor>No efforts in .scratch/.</Text>}
        {(current?.efforts ?? []).map(row)}
      </Box>
    )
  })
}
