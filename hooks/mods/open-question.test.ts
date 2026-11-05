import { expect, test } from 'claude-code/testing'

import { openQuestion } from './open-question'

test('takes the last ❓ line and drops its markdown', async () => {
  const answer = ['Done.', '', '---', '', '❓ **Should I add the rules to `~/.claude/CLAUDE.md`?**'].join('\n')
  expect(openQuestion(answer)).toBe('Should I add the rules to ~/.claude/CLAUDE.md?')
})

test('the last of several ❓ lines wins, and a bullet before the mark is fine', async () => {
  expect(openQuestion('❓ First?\n\n- ❓ Second?')).toBe('Second?')
})

test('a ❓ inside a code fence, mid-line, or alone is no question', async () => {
  expect(openQuestion('```\n❓ **<question>**\n```')).toBeNull()
  expect(openQuestion('Questions get a ❓ mark.')).toBeNull()
  expect(openQuestion('❓ **  **')).toBeNull()
  expect(openQuestion('')).toBeNull()
})
