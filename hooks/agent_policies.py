"""Shell commands three read-only agents may run on top of review_guard's read-only set.

Each agent reads untrusted input (a page, session transcripts, a project's manifests) and
needs a few commands the review set refuses. hooks/pre_tool_guard.py passes the agent's
policy to review_guard.check as `extra`, which sees each segment first:

- ui-reviewer: read-only agent-browser (any http(s) site, screenshots saved under the temp
  directory or .scratch/) and `magick` crops of those screenshots.
- session-miner: `bash` on this plugin's retro extract-signal.sh, one log per call.
- dependency-auditor: `bash` on this plugin's dependency-audit audit.sh, and the read-only
  composer (with --no-plugins and --no-scripts) and npm commands that script runs.

A plugin script must be this plugin's own file, by real path: a look-alike name elsewhere
(in the agent's memory directory, which it may write) is refused.
"""

import os
import re
import tempfile
from typing import Callable

import browser_guard
from shell_syntax import Blocked

PLUGIN_ROOT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
SESSION_NAME = re.compile(r"[\w-]+")


def plugin_script(script: str, cwd: str, rel: str) -> bool:
    real = os.path.realpath(os.path.join(cwd, os.path.expanduser(script)))
    return real == os.path.realpath(os.path.join(PLUGIN_ROOT, rel))


def check_bash_script(args: list[str], cwd: str, rel: str) -> list[str]:
    """`bash <this plugin's rel> [args]`, nothing before the script. Returns the script's args."""
    if not args or args[0].startswith("-") or not plugin_script(args[0], cwd, rel):
        raise Blocked(f"`bash` runs only this plugin's {rel} ({os.path.join(PLUGIN_ROOT, rel)})")
    return args[1:]


def save_dirs(cwd: str) -> list[str]:
    dirs = [os.path.realpath(tempfile.gettempdir()), os.path.realpath("/tmp"), os.path.join(cwd, ".scratch")]
    return list(dict.fromkeys(dirs))


# ---- ui-reviewer ------------------------------------------------------------------------------

def check_ui_browser(args: list[str], cwd: str) -> None:
    i = 0
    while i < len(args) and args[i].startswith("-"):
        a = args[i]
        if a == "--json":
            i += 1
        elif a in ("--session", "--state"):
            if i + 1 >= len(args):
                raise Blocked(f"`{a}` needs a value")
            if a == "--session" and not SESSION_NAME.fullmatch(args[i + 1]):
                raise Blocked("`--session` takes a plain name")
            i += 2
        else:
            raise Blocked(f"flag `{a}` is not allowed before the verb")
    if i >= len(args):
        raise Blocked("missing agent-browser verb")
    browser_guard.check_verb(args[i], args[i + 1:], cwd, save_dirs(cwd), None)


MAGICK_VALUE_OPS = {"-crop": re.compile(r"\d+x\d+[+-]\d+[+-]\d+"),
                    "-resize": re.compile(r"\d+(x\d+)?[%!<>]?|x\d+"),
                    "-gravity": re.compile(r"[A-Za-z]+"),
                    "-quality": re.compile(r"\d{1,3}")}
MAGICK_BOOL_OPS = {"+repage", "-trim"}
IMAGE = re.compile(r"[^:@|<>]+\.(?:png|jpe?g|webp)", re.IGNORECASE)
# ImageMagick picks a coder from the file's content, so an MVG or SVG file named x.png runs as
# one. The input must name its format (`png:/tmp/x.png`), which pins the coder to it.
INPUT_IMAGE = re.compile(r"(png|jpe?g|webp):([^:@|<>]+\.(png|jpe?g|webp))", re.IGNORECASE)


def check_magick(args: list[str], cwd: str) -> None:
    """`magick png:<screenshot> [-crop G] [+repage] … <out>`: both images under the save dirs. The
    input's format prefix is required; any other `coder:` prefix or `@file` is refused."""
    images: list[str] = []
    i = 0
    while i < len(args):
        a = args[i]
        if a in MAGICK_BOOL_OPS:
            i += 1
        elif a in MAGICK_VALUE_OPS:
            if i + 1 >= len(args) or not MAGICK_VALUE_OPS[a].fullmatch(args[i + 1]):
                raise Blocked(f"`magick {a}` needs a plain value")
            i += 2
        elif a.startswith(("-", "+")):
            raise Blocked(f"`magick {a}` is not allowed; only -crop, -resize, -gravity, -quality, -trim, +repage")
        else:
            images.append(a)
            i += 1
    if len(images) != 2:
        raise Blocked("`magick` takes one input screenshot and one output image")
    dirs = save_dirs(cwd)
    m = INPUT_IMAGE.fullmatch(images[0])
    if not m or m.group(1).lower().replace("jpg", "jpeg") != m.group(3).lower().replace("jpg", "jpeg"):
        raise Blocked("`magick` input names its format to match its extension: `magick png:/tmp/x.png …`")
    for image in (m.group(2), images[1]):
        if not IMAGE.fullmatch(image) or not any(browser_guard.inside(image, d, cwd) for d in dirs):
            raise Blocked(f"`magick` reads and writes only .png/.jpg/.webp files under {' or '.join(dirs)}")


def ui_reviewer(cwd: str) -> Callable[[str, list[str]], bool]:
    def extra(name: str, args: list[str]) -> bool:
        if name == "agent-browser":
            check_ui_browser(args, cwd)
            return True
        if name == "magick":
            check_magick(args, cwd)
            return True
        return False
    return extra


# ---- session-miner ----------------------------------------------------------------------------

def session_miner(cwd: str) -> Callable[[str, list[str]], bool]:
    def extra(name: str, args: list[str]) -> bool:
        if name != "bash":
            return False
        rest = check_bash_script(args, cwd, "skills/retro/scripts/extract-signal.sh")
        if len(rest) != 1 or rest[0].startswith("-"):
            raise Blocked("`extract-signal.sh` takes one log path")
        return True
    return extra


# ---- dependency-auditor -----------------------------------------------------------------------

COMPOSER_READ = {"outdated", "audit", "show"}
NPM_READ = {"outdated", "audit", "ls", "list", "view", "info"}
# The subcommand comes first and every flag is a known boolean or carries its value after `=`.
# A flag that takes a separate value (`composer -d outdated update`, `npm --cache outdated
# install`) would hide the real subcommand behind a word this guard reads as the subcommand.
COMPOSER_FLAGS = {"--direct", "--locked", "--no-interaction", "-n", "--no-plugins", "--no-scripts",
                  "--no-dev", "--minor-only", "--patch-only", "--major-only", "--strict", "--all",
                  "--latest", "--outdated", "--no-ansi", "--ansi", "--tree", "-D", "-a", "-l", "-o", "-m"}
COMPOSER_VALUE_FLAGS = {"--format", "--abandoned", "--ignore-severity", "--ignore"}
NPM_FLAGS = {"--json", "--long", "--all", "--parseable", "--omit-lockfile-only", "--production"}
NPM_VALUE_FLAGS = {"--depth", "--omit", "--include", "--audit-level"}
PACKAGE = re.compile(r"(@[a-z0-9._~-]+/)?[a-z0-9._~-]+(/[a-z0-9._~-]+)?(@[\w.^~<>=*|-]+)?", re.IGNORECASE)


def check_package_args(tool: str, sub: str, args: list[str], bools: set, values: set) -> list[str]:
    positional = []
    for a in args:
        name, eq, _ = a.partition("=")
        if a.startswith("-"):
            if (a in bools) or (eq and name in values):
                continue
            raise Blocked(f"`{tool} {sub} {a}` is not an allowed flag (value flags take `=`)")
        if not PACKAGE.fullmatch(a):
            raise Blocked(f"`{tool} {sub}` takes package names only, not `{a}`")
        positional.append(a)
    return positional


def check_composer(args: list[str]) -> None:
    sub = args[0] if args else ""
    if sub not in COMPOSER_READ:
        raise Blocked(f"`composer {sub}` is not read-only; only {', '.join(sorted(COMPOSER_READ))}, as the first word")
    positional = check_package_args("composer", sub, args[1:], COMPOSER_FLAGS, COMPOSER_VALUE_FLAGS)
    if sub == "audit" and positional:
        raise Blocked("`composer audit` takes no package")
    # A project's plugins and scripts are its own code: without these flags they run.
    if "--no-plugins" not in args or "--no-scripts" not in args:
        raise Blocked("`composer` needs --no-plugins and --no-scripts: the project's plugins and scripts are untrusted")


def check_npm(args: list[str]) -> None:
    sub = args[0] if args else ""
    if sub not in NPM_READ:
        raise Blocked(f"`npm {sub}` is not read-only; only {', '.join(sorted(NPM_READ))}, as the first word")
    positional = check_package_args("npm", sub, args[1:], NPM_FLAGS, NPM_VALUE_FLAGS)
    if sub == "audit" and positional:
        raise Blocked("`npm audit` takes no subcommand (`npm audit fix` changes the lockfile)")


def dependency_auditor(cwd: str) -> Callable[[str, list[str]], bool]:
    def extra(name: str, args: list[str]) -> bool:
        if name == "bash":
            rest = check_bash_script(args, cwd, "skills/dependency-audit/scripts/audit.sh")
            if rest not in ([], ["composer"], ["npm"]):
                raise Blocked("`audit.sh` takes composer, npm, or nothing")
            return True
        if name == "composer":
            check_composer(args)
            return True
        if name == "npm":
            check_npm(args)
            return True
        return False
    return extra


POLICIES = {"ui-reviewer": ui_reviewer, "session-miner": session_miner,
            "dependency-auditor": dependency_auditor}
