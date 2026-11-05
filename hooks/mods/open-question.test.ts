import { expect, test } from 'claude-code/testing'

import { openQuestions } from './open-question'

test('takes a ❓ line and drops its markdown', async () => {
  const answer = ['Done.', '', '---', '', '❓ **Should I add the rules to `~/.claude/CLAUDE.md`?**'].join('\n')
  expect(openQuestions(answer)).toEqual(['Should I add the rules to ~/.claude/CLAUDE.md?'])
})

test('every ❓ line counts, in order, and a bullet before the mark is fine', async () => {
  expect(openQuestions('❓ First?\n\n- ❓ Second?')).toEqual(['First?', 'Second?'])
})

test('a ❓ inside a code fence, mid-line, or alone is no question', async () => {
  expect(openQuestions('```\n❓ **<question>**\n```')).toEqual([])
  expect(openQuestions('Questions get a ❓ mark.')).toEqual([])
  expect(openQuestions('❓ **  **')).toEqual([])
  expect(openQuestions('')).toEqual([])
})
