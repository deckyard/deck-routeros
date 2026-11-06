#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
#
# routeros's own docs check, run by tools/check-all.sh and the test workflow.
#
# The guides, the README and the examples import the deck as `mt`, not under
# its slug, and the shared tools/check-docs.sh only reads `routeros.name(`. So
# here every `<alias>.name` they write - for each alias the deck is imported
# under (`import "@deckyard/routeros/" as mt;` or `"../src/routeros.j"`) - is
# checked against what src/ exports, the way check-docs.sh finds exports:
#
#   1  `mt.name(...)` names an exported function and passes as many arguments
#      as it takes; `mt.name(...)` with a literal `...` is prose, not counted
#   2  `mt.name` without a call names an exported function
#   3  `mt.Name`, `mt.CONST`, `mt.Struct.field`, `mt.Enum.Variant` are exported
#
# Arguments are counted with nested parentheses, brackets, braces and strings
# taken into account, so calls that check-docs.sh skips (`mt.f(os.env("X"))`)
# are counted too.
#
# Usage: tools/check-extra.sh
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=tools/deck-lib.sh
source tools/deck-lib.sh
deck_load

python3 - <<'PYALIAS'
import re, glob, os, sys

SLUG, SHAPE = os.environ['DECK_SLUG'], os.environ['DECK_SHAPE']
NAME = os.environ['DECK_NAME']
if SHAPE != 'topics':
    sys.exit(f"tools/check-extra.sh assumes a topics deck; {NAME} is {SHAPE}")

# ---- the real API, as tools/check-docs.sh reads it -------------------------
sources = [f for f in sorted(glob.glob('src/**/*.j', recursive=True))
           if not f.endswith('_test.j')]
funcs, known = {}, set()
for f in sources:
    src = open(f, encoding='utf-8').read()
    for m in re.finditer(r'^export func ([A-Za-z][A-Za-z0-9]*)\(([^)]*)\)', src, re.M):
        funcs[m.group(1)] = len([p for p in m.group(2).split(',') if p.strip()])
    for m in re.finditer(r'^export def const ([A-Z][A-Z0-9_]*) as ', src, re.M):
        known.add(m.group(1))
    for m in re.finditer(r'^export def struct ([A-Za-z]\w*) \{(.*?)\};', src, re.M | re.S):
        known.add(m.group(1))
        known |= {f"{m.group(1)}.{x.strip().split(' as ')[0].strip()}"
                  for x in m.group(2).split(',') if x.strip()}
    for m in re.finditer(r'^export def enum ([A-Za-z]\w*) \{(.*?)\n\};', src, re.M | re.S):
        known.add(m.group(1))
        body = re.sub(r'\{[^{}]*\}', '', m.group(2))
        known |= {f"{m.group(1)}.{v.strip()}" for v in body.split(',') if v.strip()}
if not funcs:
    sys.exit("tools/check-extra.sh found no exported function in src/")

# ---- the files, and the aliases they import the deck under ----------------
files = sorted(glob.glob('docs/**/*.md', recursive=True))
files += [f for f in ['README.md'] if os.path.exists(f)]
files += sorted(glob.glob('examples/**/*.j', recursive=True))
files += sorted(glob.glob('examples/**/*.md', recursive=True))
texts = {f: open(f, encoding='utf-8').read() for f in files}

target = r'(?:' + re.escape(NAME) + r'/?|(?:\.\./)*src/' + re.escape(SLUG) + r'\.j)'
aliases = set()
for text in texts.values():
    aliases |= set(re.findall(r'import\s+"' + target + r'"\s+as\s+([a-z][A-Za-z0-9]*)\s*;',
                              text))
aliases.discard(SLUG)        # tools/check-docs.sh owns the slug
if not aliases:
    sys.exit("tools/check-extra.sh: nothing imports the deck under an alias - "
             "is this check still needed?")
alias_alt = '|'.join(sorted(map(re.escape, aliases), key=len, reverse=True))

def call_args(text, start):
    """The text between the `(` at start-1 and its match, or None."""
    depth, quote, i = 1, None, start
    while i < len(text):
        c = text[i]
        if quote:
            if c == '\\' and quote == '"':
                i += 1
            elif c == quote:
                quote = None
        elif c in '"\'':
            quote = c
        elif c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
            if depth == 0:
                return text[start:i]
        i += 1
    return None

def arity(args):
    """Top-level arguments, ignoring commas nested in calls, literals, strings."""
    if not args.strip():
        return 0
    depth, quote, count, i = 0, None, 1, 0
    while i < len(args):
        c = args[i]
        if quote:
            if c == '\\' and quote == '"':
                i += 1
            elif c == quote:
                quote = None
        elif c in '"\'':
            quote = c
        elif c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        elif c == ',' and depth == 0:
            count += 1
        i += 1
    return count

problems, calls, refs = [], 0, 0
ref = re.compile(r'(?<![\w.$])(' + alias_alt +
                 r')\.([A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z]\w*)?)(\()?')
for f, text in texts.items():
    for m in ref.finditer(text):
        alias, name, paren = m.groups()
        line = text.count('\n', 0, m.start()) + 1
        where = f"{f}:{line}"
        if name[0].islower():
            name = name.split('.')[0]
            if name not in funcs:
                problems.append(f"{where}: {alias}.{name} is not an exported function")
                continue
            if not paren:
                refs += 1
                continue
            calls += 1
            args = call_args(text, m.end())
            if args is None:
                problems.append(f"{where}: {alias}.{name}( is never closed")
            elif args.strip() != '...' and arity(args) != funcs[name]:
                problems.append(f"{where}: {alias}.{name}(...) passes {arity(args)} "
                                f"argument(s), the code takes {funcs[name]}")
        else:
            refs += 1
            if name not in known:
                problems.append(f"{where}: {alias}.{name} is not exported")

if problems:
    print("", file=sys.stderr)
    for p in problems:
        print(f"  {p}", file=sys.stderr)
    print(f"\n{len(problems)} problem(s) with `{'`/`'.join(sorted(aliases))}.` "
          f"references.", file=sys.stderr)
    sys.exit(1)
print(f"{calls} `{'`/`'.join(sorted(aliases))}.` call(s) and {refs} other reference(s) "
      f"in {len(files)} docs, README and example file(s) match the code")
PYALIAS
