import { expect, test } from 'claude-code/testing'

import { duration } from './workers-model'

test('duration rounds to whole seconds before splitting minutes from seconds', async () => {
  expect(duration(0)).toBe('0s')
  expect(duration(59_400)).toBe('59s')
  // Rounding the parts apart printed `60s` and `1m60s` here.
  expect(duration(59_600)).toBe('1m00s')
  expect(duration(60_000)).toBe('1m00s')
  expect(duration(119_700)).toBe('2m00s')
  expect(duration(125_000)).toBe('2m05s')
})
