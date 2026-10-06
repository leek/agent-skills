import { expect, mock, test } from 'claude-code/testing'

// Stands in for Claude Code's own drawing beneath the plugin: an empty box.
const engineDraw = ($: any, e: any) => {
  const { Box } = $.ui.resolve(e)
  return <Box key="engine" />
}

const BAND = {
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: true, maxRows: 8, bodyColumns: 100 },
} as const

const PANE = {
  component: 'Pane',
  requestId: 'scratch',
  props: { title: 'Scratch', isFocused: false, bodyColumns: 100, placement: 'dock' },
} as const

for (const surface of ['terminal', 'desktop'] as const) {
  test(`workers band follows a subagent from spawn to answer (${surface})`, async ($, on) => {
    mock.clock(on, { now: 1_000 })
    on('ui.render', async ($, e) => engineDraw($, e))
    on('agent.spawn', async () => ({ model: 'haiku', agentId: 'a1' }))
    on('tool.call', async () => ({ result: 'ok' }) as never)
    on('turn.complete', async () => ({ text: '' }))

    const band = await $.ui.mount({ plugin: 'leek-skills', surface, ...BAND } as never)
    expect(await band.find({ type: 'Text', text: /Workers/ })).toBeUndefined()

    await $.agent.spawn({ prompt: 'review', description: 'review auth diff', subagentType: 'leek-skills:pr-reviewer' } as never)
    await $.tool.call({ tool: 'Bash', command: 'git diff main', tool_use_id: 't1', agentId: 'a1' } as never)
    expect(await band.find({ type: 'Text', text: /Workers 0\/1 done/ })).toBeDefined()
    expect(await band.find({ type: 'Text', text: /review auth diff · 1 tools .*Bash: git diff main/ })).toBeDefined()

    await $.turn.complete({ agentId: 'a1', reason: 'answer', answer: '', durationMs: 5, isAborted: false, turnId: 'x' })
    expect(await band.find({ type: 'Text', text: /Workers 1\/1 done/ })).toBeDefined()

    await band.press({ key: 'hide' })
    expect(await band.find({ type: 'Text', text: /Workers/ })).toBeUndefined()
  })
}

test('main-loop tool calls are not counted as workers', async ($, on) => {
  on('ui.render', async ($, e) => engineDraw($, e))
  on('tool.call', async () => ({ result: 'ok' }) as never)
  await $.tool.call({ tool: 'Bash', command: 'ls', tool_use_id: 't1' } as never)

  const band = await $.ui.mount({ plugin: 'leek-skills', surface: 'terminal', ...BAND } as never)
  expect(await band.find({ type: 'Text', text: /Workers/ })).toBeUndefined()
})

test('/scratch answers with the table and draws the board', async ($, on) => {
  const files: Record<string, string> = {
    '/repo/.scratch/auth/spec.md': '---\ntitle: Auth\nstatus: ready-for-agent\n---\n',
    '/repo/.scratch/auth/tickets/01-login.md': '---\ntitle: Login form\nstatus: ready-for-agent\nblocked-by: []\n---\n',
  }
  on('ui.render', async ($, e) => engineDraw($, e))
  mock.clock(on, { now: 0 })
  on('session.cwd', async () => ({ value: '/repo' }) as never)
  on('fs.exists', async (_$, e) => ({ value: e.path === '/repo/.scratch' }) as never)
  on('fs.read', async (_$, e) => ({ value: files[(e as { path: string }).path] ?? '' }) as never)
  on('fs.list', async (_$, e) => {
    const names = new Map<string, 'file' | 'dir'>()
    for (const full of Object.keys(files)) {
      if (!full.startsWith(`${e.path}/`)) continue
      const parts = full.slice(e.path.length + 1).split('/')
      names.set(parts[0] ?? '', parts.length > 1 ? 'dir' : 'file')
    }
    const value = [...names].map(([name, kind]) => ({ name, kind, size: 1, mtimeMs: 0, isLink: false }))
    return { value } as never
  })
  on('ui.open', async () => ({ value: { isPlaced: true } }) as never)

  const answer = await $.command.run({ command: 'scratch', args: '' } as never)
  expect(answer.text).toContain('| `auth` | open |')
  expect(answer.text).toContain('/implement .scratch/auth/tickets/01-login.md')

  const pane = await $.ui.mount({ plugin: 'leek-skills', surface: 'terminal', ...PANE } as never)
  expect(await pane.find({ type: 'Text', text: /01 Login form/ })).toBeDefined()
})
