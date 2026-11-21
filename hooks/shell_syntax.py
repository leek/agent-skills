"""Shared bash/zsh shell tokenizer and read-only filter checks for PreToolUse guards.

Tokenizes commands under rules that hold in both bash and zsh, tracking quotes
itself: blocks unquoted newlines and any \\r, command/process/arithmetic
substitutions (``, $(), =(), $[], and ${( in double quotes), unsafe redirects and
background operators (<, >, <(, >(, |&, &), and unquoted subshells or zsh glob
qualifiers ((, )). Quoted or escaped operators and newlines stay data, and a
backslash-newline is a line continuation.
"""

SAFE_REDIRECTS = {("2", ">", "/dev/null"), ("2", ">&", "1")}
OPERATOR_CHARS = set("();<>|&")
SEPARATORS = {"&&", "||", ";", "|"}
UNIQ_VALUE_FLAGS = {"-f", "-s", "-w", "--skip-fields", "--skip-chars", "--check-chars"}

# `${X:--o}` is `-o` when X is unset, and "$X" is whatever the environment holds: either way
# the command gets an argument the checks never read.
PARAMETER_REASON = "parameter expansion ($VAR, ${VAR}) is not allowed; write the value, or single-quote a literal $"


class Blocked(Exception):
    pass


class Op(str):
    """An unquoted shell operator run (`&&`, `|`, `>`, `(` …), as opposed to a word."""


class Word(str):
    """A shell word, with `unquoted` marking which of its characters the shell may still expand."""

    unquoted: str = ""
    glued: bool = False  # an operator follows with no space between: `2>` but not `2 >`
    has_quotes: bool = False  # any quote or backslash appeared (disqualifies IO_NUMBER)


def check_expansion(word: "Word") -> None:
    """Refuse a word the shell would expand into arguments this guard never sees.

    The checks below read the word as typed, but the shell expands it first: `-de*` or `*`
    can become a file named `-delete` or `-oout`, `a*` can become two files where a check
    counted one argument, and `{-o,out}` becomes `-o out`. So every unquoted glob is refused;
    a quoted one (`-g '*.php'`, `-name '*.php'`) reaches the command as written.

    Braces nest (`{-o,o{u}t}`), so no pattern is matched: any unquoted `{` with an unquoted
    `,` or `..` in the same word is refused. `^` and `#` are zsh extended-glob operators
    (`^x` is every file but x, `inA^x` can be several files and so add an argument), so they
    are refused too, which means a revision such as `HEAD^` must be quoted. A `~` after the
    first character is one as well, but `X~Y` (X free of other glob characters) can only become
    the file X itself or stay as typed, never more words; so it is refused only in a word that
    starts with `-`, where a file named X could become a flag (`-delete~x`). `HEAD~3` passes.
    """
    live = word.unquoted
    if "{" in live and ("," in live or ".." in live):
        raise Blocked("brace expansion is not allowed; write the arguments out, or quote the word")
    # The dash test reads the whole word: `'-'delete~x` and `\-delete~x` start with `-` once dequoted.
    if any(c in live for c in "*?[^#") or ("~" in live and str(word).startswith("-")):
        raise Blocked("an unquoted glob character (* ? [ ^ # ~) is not allowed; quote the word, "
                      "as in 'HEAD^' or -g '*.php'")


def is_parameter(command: str, at: int) -> bool:
    """True for a `$` the shell may expand. Deny by default: zsh has more forms (`$=x`, `$~x`,
    `$^x`, `$+x`) than any list holds, so `$` is literal only at the end of a word or quote."""
    return command[at] == "$" and at + 1 < len(command) and command[at + 1] not in ' \t\n"'


def join_continuations(command: str) -> str:
    """Drop every backslash-newline the shell would drop, before anything else looks.

    The shell joins the lines first, so `$`, backslash-newline, `(rm x)` is `$(rm x)`, and
    `$`, backslash-newline, `X` is `$X`; a check that reads one character ahead must see the joined text. Single quotes
    keep a backslash-newline as data.
    """
    out: list[str] = []
    i, n, quote = 0, len(command), ""
    while i < n:
        c = command[i]
        if quote == "'":
            if c == "'":
                quote = ""
        elif c == "\\" and i + 1 < n:
            if command[i + 1] != "\n":
                out.append(command[i:i + 2])
            i += 2
            continue
        elif c in "'\"":
            quote = "" if quote == c else (quote or c)
        out.append(c)
        i += 1
    return "".join(out)


def tokenize(command: str) -> list[str]:
    """Split a command into words and Op tokens, the way bash and zsh both would.

    Quoting is tracked here rather than by shlex, so a quoted or escaped `(`, `>` or
    newline stays data inside its word, while the same character unquoted becomes an
    operator or blocks the command. Anything this tokenizer is unsure of is blocked.
    """
    command = join_continuations(command)
    tokens: list[str] = []
    word: list[str] = []
    live: list[str] = []  # the same word with every quoted or escaped character blanked
    in_word = False
    has_quotes = False
    i, n = 0, len(command)

    def flush(glued: bool = False) -> None:
        nonlocal word, live, in_word, has_quotes
        if in_word:
            token = Word("".join(word))
            token.unquoted = "".join(live)
            token.glued = glued
            token.has_quotes = has_quotes
            tokens.append(token)
        word, live, in_word, has_quotes = [], [], False, False

    def quoted(text: str) -> None:
        word.append(text)
        live.append("\0" * len(text))

    while i < n:
        c = command[i]
        if c == "\r":
            raise Blocked("multi-line commands are not allowed")
        if c == "\\":
            if i + 1 >= n:
                raise Blocked("could not parse the command (trailing backslash)")
            if command[i + 1] == "\n":  # line continuation
                i += 2
                continue
            quoted(command[i + 1])
            in_word = True
            has_quotes = True
            i += 2
            continue
        if c == "'":
            end = command.find("'", i + 1)
            if end < 0:
                raise Blocked("could not parse the command (no closing quotation)")
            quoted(command[i + 1:end])
            in_word = True
            has_quotes = True
            i = end + 1
            continue
        if c == '"':
            j = i + 1
            while True:
                if j >= n:
                    raise Blocked("could not parse the command (no closing quotation)")
                d = command[j]
                if d == '"':
                    break
                # Double quotes still expand: refuse every substitution form inside them,
                # escaped or not, since zsh's (e) flag can re-evaluate an escaped one.
                if d == "`" or command.startswith(("$(", "$[", "${("), j):
                    raise Blocked("command substitution is not allowed")
                if is_parameter(command, j):
                    raise Blocked(PARAMETER_REASON)
                if d == "\\" and j + 1 < n and command[j + 1] in '"\\$`\n':
                    if command[j + 1] != "\n":
                        quoted(command[j + 1])
                    j += 2
                    continue
                quoted(d)
                j += 1
            in_word = True
            has_quotes = True
            i = j + 1
            continue
        if c == "`" or command.startswith(("$(", "$[", "=(", "$'"), i):
            if command.startswith("$'", i):
                raise Blocked("$'…' quoting is not allowed")
            raise Blocked("command substitution is not allowed")
        if is_parameter(command, i):
            raise Blocked(PARAMETER_REASON)
        if c == "\n":
            raise Blocked("multi-line commands are not allowed")
        if c in " \t":
            flush()
            i += 1
            continue
        if c == "#" and not in_word:
            # Both shells start a comment here, and a comment hides quotes from them but
            # not from this tokenizer: `echo # '<newline>rm x #'` would run `rm x`.
            raise Blocked("comments are not allowed")
        if c in OPERATOR_CHARS:
            flush(glued=True)
            j = i
            while j < n and command[j] in OPERATOR_CHARS:
                j += 1
            tokens.append(Op(command[i:j]))
            i = j
            continue
        word.append(c)
        live.append(c)
        in_word = True
        i += 1
    flush()
    return tokens


def segments(command: str) -> list[list[str]]:
    tokens = tokenize(command)
    cleaned, i = [], 0
    while i < len(tokens):
        window = tokens[i:i + 3]
        # `2>/dev/null` is a redirect only when the 2 is completely unquoted (no empty quotes
        # like `""2` or `2""` either) and touches the operator. `"2">/dev/null`, `""2>/dev/null`,
        # and `2 >/dev/null` pass 2 as an argument and redirect stdout, so stripping them would
        # hide an argument from the checks (`uniq -f ""2>/dev/null - /tmp/out`).
        if (len(window) == 3 and not isinstance(window[0], Op) and isinstance(window[1], Op)
                and not isinstance(window[2], Op) and tuple(window) in SAFE_REDIRECTS
                and window[0].glued and not window[0].has_quotes
                and window[0].unquoted == str(window[0])):
            i += 3
            continue
        cleaned.append(tokens[i])
        i += 1
    out, current = [], []
    for token in cleaned:
        if isinstance(token, Op) and token in SEPARATORS:
            if current:
                out.append(current)
            current = []
        elif isinstance(token, Op):
            if any(c in token for c in "<>&"):
                raise Blocked("redirects are not allowed")
            raise Blocked("subshells and glob qualifiers are not allowed")
        else:
            current.append(str(token))
    if current:
        out.append(current)
    # After the operator checks, so an operator is reported before the glob beside it.
    for token in cleaned:
        if isinstance(token, Word):
            check_expansion(token)
    return out


def parse_command(command: str) -> list[list[str]]:
    parts = segments(command)
    if not parts:
        raise Blocked("empty command")
    return parts


def long_option_in(arg: str, names: tuple[str, ...]) -> bool:
    """True when arg is one of names, carries a value or suffix after one, or abbreviates one.

    GNU getopt and git's parse-options accept any unambiguous prefix of a long option, so
    `--out=x` is `--output=x`; matching only the full spelling lets the short form through.
    """
    if not arg.startswith("--") or arg == "--":
        return False
    name = arg.split("=", 1)[0]
    return any(name.startswith(n) or n.startswith(name) for n in names)


def check_filter(name: str, args: list[str]) -> None:
    """Refuse the text-filter forms that write a file or run a program."""
    if name == "sort":
        for a in args:
            if long_option_in(a, ("--output", "--compress-program")) or (
                    a.startswith("-") and not a.startswith("--") and "o" in a[1:]):
                raise Blocked("`sort -o` and `--compress-program` write files or run a program")
    elif name == "uniq":
        positional, skip, ended = 0, False, False
        for a in args:
            if skip:
                skip = False
            elif not ended and a == "--":
                ended = True
            elif not ended and a in UNIQ_VALUE_FLAGS:
                skip = True
            elif ended or positional or a == "-" or not a.startswith("-"):
                # BSD uniq stops reading options at the first operand, so in
                # `uniq in -out` the second word is the output file.
                positional += 1
        if positional > 1:
            raise Blocked("`uniq <in> <out>` writes a file")
