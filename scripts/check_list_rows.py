#!/usr/bin/env python3
"""The 1.7 design's lists (CLAUDE.md, Conventions): every List and Form gets
.plowRGrouped() (the page colour behind it), and every Section, and every
ForEach sitting straight in a List, gets .listRowBackground(PlowRColor.surface)
(the card colour). Sections in a Menu, Picker, context menu or dialog are
skipped. A missed one only shows in dark mode, as a grey card among green.

  python3 scripts/check_list_rows.py --check FILES   # the guard: lists what's missing
  python3 scripts/check_list_rows.py FILES           # adds what's missing

Swift is scanned with balanced brackets, skipping strings and comments.
Not checked: rows of List(data) { row }, bare rows straight in a List/Form,
rows built in helper properties. Put those in a Section or add by hand."""

import re, sys

def skip_string(s, i):
    # s[i] == '"'
    if s.startswith('"""', i):
        j = s.index('"""', i + 3)
        return j + 3
    j = i + 1
    depth = 0
    while j < len(s):
        c = s[j]
        if c == '\\':
            if s[j+1] == '(':
                # interpolation: match parens inside
                k = match(s, j + 1, '(', ')')
                j = k
                continue
            j += 2; continue
        if c == '"': return j + 1
        j += 1
    raise ValueError('unterminated string')

def match(s, i, o, c):
    # s[i] == o ; return index after matching c
    depth = 0; j = i
    while j < len(s):
        ch = s[j]
        if s.startswith('//', j):
            j = s.index('\n', j); continue
        if s.startswith('/*', j):
            j = s.index('*/', j) + 2; continue
        if ch == '"':
            j = skip_string(s, j); continue
        if ch == o: depth += 1
        elif ch == c:
            depth -= 1
            if depth == 0: return j + 1
        j += 1
    raise ValueError('unbalanced')

def end_of_call(s, i):
    """i just after the keyword; consume (args) {body} trailing-label closures."""
    j = i
    progressed = False
    while True:
        k = j
        while k < len(s) and s[k] in ' \t\n': k += 1
        if k < len(s) and s[k] == '(' and not progressed:
            j = match(s, k, '(', ')'); progressed = True; continue
        if k < len(s) and s[k] == '{':
            j = match(s, k, '{', '}'); progressed = True; continue
        m = re.match(r'(header|footer)\s*:', s[k:])
        if m and progressed:
            j = k + m.end(); continue
        return j if progressed else None

def code_positions(s, pattern):
    """Matches of pattern outside strings/comments."""
    out = []; j = 0
    rx = re.compile(pattern)
    while j < len(s):
        if s.startswith('//', j): j = s.index('\n', j); continue
        if s.startswith('/*', j): j = s.index('*/', j) + 2; continue
        if s[j] == '"': j = skip_string(s, j); continue
        m = rx.match(s, j)
        if m: out.append(m); j = m.end(); continue
        j += 1
    return out

def enclosing_keywords(s, pos):
    """Every enclosing view's identifier, innermost first. Control flow
    (if, else, switch cases, ForEach's own row closures aside) and Group
    pass through to the view that holds them."""
    out = []
    while True:
        k = enclosing_keyword(s, pos)
        if k is None: return out
        name, at = k
        line = s[s.rfind('\n', 0, at) + 1:at].strip()
        if not (re.match(r'(\}\s*)?(if|else|switch|case|guard)\b', line) or name == 'Group'):
            out.append(name)
        pos = at

def enclosing_keyword(s, pos):
    """(identifier, position of its '{') for the '{' that encloses pos, or None."""
    depth = 0; j = pos - 1
    while j >= 0:
        c = s[j]
        if c == '}': depth += 1
        elif c == '{':
            if depth == 0:
                k = j - 1
                while k >= 0 and s[k] in ' \t\n': k -= 1
                if s[k] == ')':  # skip (args)
                    d = 0
                    while k >= 0:
                        if s[k] == ')': d += 1
                        elif s[k] == '(':
                            d -= 1
                            if d == 0: k -= 1; break
                        k -= 1
                m = re.search(r'([A-Za-z_]\w*)\s*$', s[:k+1])
                return (m.group(1) if m else '', j)
            depth -= 1
        j -= 1
    return None

def apply(s, keyword, modifier):
    inserts = []
    for m in code_positions(s, r'(?<![\w.])' + keyword + r'(?=\s*[({])'):
        enclosing = enclosing_keywords(s, m.start())
        if keyword == 'Section' and set(enclosing) & {'Menu', 'Picker', 'contextMenu', 'confirmationDialog'}:
            continue
        # A ForEach's rows need the colour only when they sit straight in a List.
        if keyword == 'ForEach' and (not enclosing or enclosing[0] != 'List'):
            continue
        end = end_of_call(s, m.end())
        if end is None: continue
        # A ForEach's own modifiers (onDelete, onMove, onInsert) stay on it.
        while True:
            t = re.match(r'\s*\.(onDelete|onMove|onInsert)(?=\s*[({])', s[end:])
            if not t: break
            end = end_of_call(s, end + t.end())
        if s[end:end+200].lstrip().startswith(modifier.split('(')[0]): continue
        line_start = s.rfind('\n', 0, m.start()) + 1
        indent = re.match(r'[ \t]*', s[line_start:]).group(0)
        inserts.append((end, '\n' + indent + modifier))
    for pos, text in sorted(inserts, reverse=True):
        s = s[:pos] + text + s[pos:]
    return s, len(inserts)


RULES = [('Section', '.listRowBackground(PlowRColor.surface)'),
         ('ForEach', '.listRowBackground(PlowRColor.surface)'),
         ('(?:List|Form)', '.plowRGrouped()')]

def main(argv):
    check = '--check' in argv
    paths = [a for a in argv if a != '--check']
    missing = []
    for path in paths:
        s = open(path).read()
        out = s
        for keyword, modifier in RULES:
            out, n = apply(out, keyword, modifier)
            if n and check:
                missing.append(f'{path}: {n} {keyword.strip("(?:)")} without {modifier}')
        if not check and out != s:
            open(path, 'w').write(out)
            print(f'fixed {path}')
    if check:
        for line in missing: print(line)
        if missing:
            print('Every List/Form needs .plowRGrouped(), and every Section (and every ForEach straight in a List) '
                  '.listRowBackground(PlowRColor.surface): fix with python3 scripts/check_list_rows.py $(find PlowR/Views -name "*.swift")')
            return 1
        print('List rows check passed.')
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
