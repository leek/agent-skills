// Pure helper for the question band: the reply's last ❓ line, the non-blocking question the
// reply leaves for the user (the convention: `❓ **<question>**`, last, after a `---` line).

const MARK = '❓'

/** The text of the last line that starts with ❓ outside a code fence, or null when there is none. */
export function openQuestion(answer: string): string | null {
  let isFenced = false
  let found: string | null = null
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
      found = text
    }
  }

  return found
}
