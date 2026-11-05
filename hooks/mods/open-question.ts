// Pure helper for the question band: the reply's ❓ lines, the non-blocking questions the
// reply leaves for the user (the convention: `❓ **<question>**`, last, after a `---` line).

const MARK = '❓'

/** The text of every line that starts with ❓ outside a code fence, in reply order. */
export function openQuestions(answer: string): string[] {
  let isFenced = false
  const found: string[] = []
  for (const raw of answer.split('\n')) {
    const line = raw.trim()
    if (/^(```|~~~)/.test(line)) {
      isFenced = !isFenced
      continue
    }
    // A list bullet or a quote marker may come before the mark.
    const body = line.replace(/^([-*+]|\d+[.)]|>)\s+/, '')
    if (isFenced || !body.startsWith(MARK)) {
      continue
    }
    const text = body
      .slice(MARK.length)
      .replace(/\*\*|__|`/g, '')
      .replace(/\s+/g, ' ')
      .trim()
    if (text !== '') {
      found.push(text)
    }
  }

  return found
}
