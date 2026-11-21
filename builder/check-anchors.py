#!/usr/bin/env python3
"""Static anchor lint: check every patch literal in tweaks/*/apply.sh against
a stock rootfs.

The installer dies at runtime when an anchor is missing or ambiguous, but that
check only fires on the unit. This script runs the same reasoning offline: it
parses the patch helper calls out of every apply.sh, resolves each target file,
and counts the literal occurrences a helper will require against a stock root.

Calls are simulated in order, exactly like a dry run: a patch that renames a
function earlier in the same apply.sh satisfies a later anchor that uses the
renamed name. Mutations live in memory only; the stock files on disk are never
touched.

Usage:

    OPENCMU_STOCK_ROOT=/path/to/rootfs builder/check-anchors.py
    builder/check-anchors.py --root /path/to/rootfs

Exit status: 0 when nothing failed, 1 when any anchor failed, 2 when the stock
root is missing. WARN lines are informational and never fail the run.

Count semantics are derived from installer/lib/patch.sh: they are line counts
of a fixed-string literal, exactly what grep -cF would report.
"""

import argparse
import os
import re
import sys

# name -> (min_args, max_args) counting without the FILE argument.
HELPERS = {
    "patch_subst": (3, 3),
    "patch_subst_all": (3, 4),
    "patch_number": (4, 4),
    "patch_quoted_value": (3, 3),
    "patch_key_value": (3, 3),
    "patch_line_after_once": (4, 5),
    "insert_after_once": (4, 4),
    "insert_before_once": (4, 4),
    "append_once": (3, 3),
    "prepend_once": (3, 3),
    "sm_disable_services": (2, 99),
    "sm_set_attribute": (3, 99),
    "sm_set_affinity": (3, 99),
    "sm_add_child": (3, 3),
}

INSERT_HELPERS = ("insert_after_once", "insert_before_once")
ADD_HELPERS = ("append_once", "prepend_once")

FAILURES = []
WARNINGS = []


def fail(tweak, msg):
    FAILURES.append("%s: %s" % (tweak, msg))


def warn(tweak, msg):
    WARNINGS.append("%s: %s" % (tweak, msg))


def split_commands(text):
    """Split a sh script into command strings.

    Unlike line-based joining, this handles multi-line quoted arguments (NEW
    may span lines in patch_line_after_once) and backslash continuations.
    Comments are dropped."""
    cmds = []
    cur = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "\\" and i + 1 < n and text[i + 1] == "\n":
            cur.append(" ")
            i += 2
            continue
        if c == "#" and (not cur or cur[-1] in " \t"):
            j = text.find("\n", i)
            if j < 0:
                break
            i = j
            continue
        if c == "\n":
            if cur:
                cmds.append("".join(cur))
                cur = []
            i += 1
            continue
        if c in "\"'":
            q = c
            cur.append(c)
            i += 1
            while i < n:
                cur.append(text[i])
                if text[i] == q:
                    i += 1
                    break
                i += 1
            continue
        cur.append(c)
        i += 1
    if cur:
        cmds.append("".join(cur))
    return [c for c in cmds if c.strip()]


VAR_RE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-((?:[^{}]|\})*))?\}"
                    r"|\$([A-Za-z_][A-Za-z0-9_]*)")


def tokenize(s):
    """Split one command into word tokens.

    Handles single quotes, double quotes (including \\"), $VAR, ${VAR} and
    ${VAR:-default}, newlines inside quotes, and concatenation within one
    word. Tokens are lists of (kind, value) parts with kind 'lit' or 'var';
    a 'var' part carries "name" or "name=default" (braces form)."""
    tokens = []
    i, n = 0, len(s)
    while i < n:
        while i < n and s[i] in " \t\n":
            i += 1
        if i >= n:
            break
        parts = []
        while i < n and s[i] not in " \t\n":
            c = s[i]
            if c == "'":
                j = s.find("'", i + 1)
                if j < 0:
                    raise ValueError("unterminated single quote")
                parts.append(("lit", s[i + 1:j]))
                i = j + 1
            elif c == '"':
                i += 1
                buf = ""
                while i < n and s[i] != '"':
                    if s[i] == "\\" and i + 1 < n and s[i + 1] in '"\\$`':
                        buf += s[i + 1]
                        i += 2
                    elif s[i] == "$":
                        m = VAR_RE.match(s, i)
                        if m:
                            parts.append(("lit", buf))
                            buf = ""
                            parts.append(var_part(m))
                            i = m.end()
                        else:
                            buf += s[i]
                            i += 1
                    else:
                        buf += s[i]
                        i += 1
                if i >= n:
                    raise ValueError("unterminated double quote")
                parts.append(("lit", buf))
                i += 1
            elif c == "$":
                m = VAR_RE.match(s, i)
                if m:
                    parts.append(var_part(m))
                    i = m.end()
                else:
                    parts.append(("lit", c))
                    i += 1
            else:
                parts.append(("lit", c))
                i += 1
        tokens.append(parts)
    return tokens


def var_part(m):
    if m.group(1) is not None:  # ${NAME} or ${NAME:-default}
        if m.group(2) is None:
            return ("var", m.group(1))
        return ("var", "%s=%s" % (m.group(1), m.group(2)))
    return ("var", m.group(3))  # $NAME


def word_value(parts, variables):
    """Resolve one token to a literal value, or None when it needs a variable
    that is not statically known."""
    out = ""
    for kind, val in parts:
        if kind == "lit":
            out += val
        else:
            if "=-" in val or "=" in val:
                name, default = val.split("=", 1)
                if name in variables and variables[name] is not None:
                    out += variables[name]
                else:
                    out += default
            elif val == "OPENCMU_ROOT":
                # Symbolic: keeps $OPENCMU_ROOT/... words resolvable even
                # though the real root is only known at check time.
                out += "OPENCMU_ROOT"
            elif val in variables and variables[val] is not None:
                out += variables[val]
            else:
                return None
    return out


def collect_assignments(commands, tweak_dir):
    """Map NAME -> resolved value for simple `name=value` assignments.

    Unknown right-hand sides map to None so call sites can WARN-skip."""
    variables = {"dir": tweak_dir}
    for cmd in commands:
        m = re.match(r"^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$", cmd, re.S)
        if not m:
            continue
        name, rhs = m.group(1), m.group(2).strip()
        if rhs.startswith("$(") or rhs.startswith("`"):
            variables[name] = None
            continue
        try:
            tokens = tokenize(rhs)
        except ValueError:
            variables[name] = None
            continue
        if len(tokens) == 1:
            variables[name] = word_value(tokens[0], variables)
        else:
            variables[name] = None
    return variables


def resolve_target(value):
    """Return a root-relative path for a resolved target word, or None."""
    if value is None:
        return None
    if value.startswith("$OPENCMU_ROOT/"):
        return value[len("$OPENCMU_ROOT/"):]
    if value.startswith("OPENCMU_ROOT/"):
        return value[len("OPENCMU_ROOT/"):]
    return None


def count_lines(text, needle):
    return sum(1 for line in text.split("\n") if needle in line)


def find_line(lines, needle):
    for idx, line in enumerate(lines):
        if needle in line:
            return idx
    return -1


class Sim:
    """Per-tweak simulation state: text of each target file, mutated in order,
    plus the pristine stock text for already-patched detection."""

    def __init__(self, root):
        self.root = root
        self.current = {}
        self.stock = {}

    def read(self, rel):
        if rel not in self.current:
            path = os.path.join(self.root, rel)
            with open(path, "r", encoding="utf-8", errors="surrogateescape") as fh:
                text = fh.read()
            self.current[rel] = text
            self.stock[rel] = text
        return self.current[rel]

    def write(self, rel, text):
        self.current[rel] = text

    def is_stock(self, rel, needle):
        return needle in self.stock[rel]


def subst_once(text, old, new):
    idx = text.find(old)
    return text[:idx] + new + text[idx + len(old):]


def check_call(tweak, sim, helper, args, tweak_dir, variables):
    def word(tok):
        return word_value(tok, variables)

    def block_text(value):
        """Load an insert/append block when it points at a real file inside
        the tweak directory; runtime-generated blocks return None."""
        if value is None or not os.path.isabs(value):
            return None
        if not value.startswith(tweak_dir + os.sep):
            return None
        if not os.path.isfile(value):
            fail(tweak, "block file missing in the repo: %s" % value)
            return None
        with open(value, "r", encoding="utf-8", errors="surrogateescape") as fh:
            return fh.read()

    if helper in ADD_HELPERS or helper in INSERT_HELPERS:
        rel = resolve_target(word(args[0]))
        if rel is None:
            warn(tweak, "%s target not static; skipped" % helper)
            return
        if helper in ADD_HELPERS:
            marker = word(args[1])
            anchor = None
            block = block_text(word(args[2]))
        else:
            marker = word(args[1])
            anchor = word(args[2])
            block = block_text(word(args[3]))
        if marker is None or (anchor is None and helper in INSERT_HELPERS):
            warn(tweak, "%s marker/anchor not static; skipped" % helper)
            return
        text = sim.read(rel)
        c = count_lines(text, marker)
        if c != 0:
            fail(tweak, "%s marker already present (%d lines) in %s: %s"
                 % (helper, c, rel, marker))
            return
        if anchor is not None:
            lines = text.split("\n")
            c = count_lines(text, anchor)
            if c != 1:
                fail(tweak, "%s anchor matched %d lines in %s: %s"
                     % (helper, c, rel, anchor))
                return
        if block is not None:
            if helper == "insert_before_once":
                lines = text.split("\n")
                idx = find_line(lines, anchor)
                lines.insert(idx, block.rstrip("\n"))
                sim.write(rel, "\n".join(lines))
            elif helper == "insert_after_once":
                lines = text.split("\n")
                idx = find_line(lines, anchor)
                lines.insert(idx + 1, block.rstrip("\n"))
                sim.write(rel, "\n".join(lines))
            elif helper == "append_once":
                sim.write(rel, text.rstrip("\n") + "\n" + block.rstrip("\n")
                          + "\n")
            else:  # prepend_once
                sim.write(rel, block.rstrip("\n") + "\n" + text)
        return

    rel = resolve_target(word(args[0]))
    if rel is None:
        warn(tweak, "%s target not static; skipped" % helper)
        return
    text = sim.read(rel)
    lines = text.split("\n")

    if helper == "patch_subst":
        old = word(args[1])
        new = word(args[2])
        if old is None:
            warn(tweak, "patch_subst literal not static; skipped")
            return
        c = count_lines(text, old)
        if c == 1:
            sim.write(rel, subst_once(text, old, new or ""))
            return
        if c == 0 and new is not None and old not in sim.stock[rel] \
                and count_lines(sim.stock[rel], new) > 0:
            fail(tweak, "patch_subst NEW already present in stock %s: %s"
                 % (rel, new))
        elif c == 0 and new is not None and sim.is_stock(rel, new):
            # an earlier simulated call in this apply produced it
            return
        else:
            fail(tweak, "patch_subst anchor matched %d lines in %s: %s"
                 % (c, rel, old))
    elif helper == "patch_subst_all":
        old = word(args[1])
        new = word(args[2])
        need = 1
        if len(args) > 3:
            m = word(args[3])
            if m is not None and m.isdigit():
                need = int(m)
        if old is None:
            warn(tweak, "patch_subst_all literal not static; skipped")
            return
        c = count_lines(text, old)
        if c >= need:
            sim.write(rel, text.replace(old, new or ""))
            return
        if c == 0 and new is not None and old not in sim.stock[rel] \
                and count_lines(sim.stock[rel], new) > 0:
            fail(tweak, "patch_subst_all NEW already present in stock %s: %s"
                 % (rel, new))
        elif c == 0 and new is not None and sim.is_stock(rel, new):
            return
        else:
            fail(tweak, "patch_subst_all matched %d lines, needs %d, in %s: %s"
                 % (c, need, rel, old))
    elif helper == "patch_number":
        key = word(args[1])
        old = word(args[2])
        new = word(args[3])
        if key is None or old is None:
            warn(tweak, "patch_number literals not static; skipped")
            return
        c = count_lines(text, key)
        if c != 1:
            fail(tweak, "patch_number key matched %d lines in %s: %s"
                 % (c, rel, key))
            return
        idx = find_line(lines, key)
        if old in lines[idx]:
            lines[idx] = lines[idx].replace(old, new or "", 1)
            sim.write(rel, "\n".join(lines))
            return
        if new is not None and new in lines[idx]:
            if new in sim.stock[rel]:
                fail(tweak, "patch_number NEW already on the key line in "
                            "stock %s: %s" % (rel, key))
            return
        fail(tweak, "patch_number value not on the key line in %s: %s"
             % (rel, key))
    elif helper == "patch_quoted_value":
        key = word(args[1])
        new = word(args[2])
        if key is None:
            warn(tweak, "patch_quoted_value key not static; skipped")
            return
        c = count_lines(text, key)
        if c != 1:
            fail(tweak, "patch_quoted_value key matched %d lines in %s: %s"
                 % (c, rel, key))
            return
        idx = find_line(lines, key)
        k = lines[idx].index(key)
        rest = lines[idx][k + len(key):]
        colon = rest.find(":")
        q1 = rest.find('"', colon + 1) if colon >= 0 else -1
        if colon < 0 or q1 < 0:
            fail(tweak, "patch_quoted_value no quoted value after %r in %s: %s"
                 % (":", rel, key))
            return
        q2 = rest.find('"', q1 + 1)
        if q2 < 0:
            fail(tweak, "patch_quoted_value unterminated quoted value in %s: %s"
                 % (rel, key))
            return
        if new is not None:
            lines[idx] = (lines[idx][:k + len(key) + colon + q1 + 1] + new
                          + lines[idx][k + len(key) + colon + q2:])
            sim.write(rel, "\n".join(lines))
    elif helper == "patch_key_value":
        key = word(args[1])
        new = word(args[2])
        if key is None:
            warn(tweak, "patch_key_value key not static; skipped")
            return
        c = count_lines(text, key)
        if c != 1:
            fail(tweak, "patch_key_value key matched %d lines in %s: %s"
                 % (c, rel, key))
            return
        idx = find_line(lines, key)
        k = lines[idx].index(key)
        eq = lines[idx].find("=", k)
        if eq < 0:
            fail(tweak, "patch_key_value no '=' after the key in %s: %s"
                 % (rel, key))
            return
        if new is not None:
            lines[idx] = lines[idx][:eq + 1] + " " + new
            sim.write(rel, "\n".join(lines))
    elif helper == "patch_line_after_once":
        anchor = word(args[1])
        old = word(args[2])
        new = word(args[3])
        if anchor is None or old is None:
            warn(tweak, "patch_line_after_once literals not static; skipped")
            return
        c = count_lines(text, anchor)
        if c != 1:
            fail(tweak, "patch_line_after_once anchor matched %d lines in %s: "
                        "%s" % (c, rel, anchor))
            return
        start = find_line(lines, anchor)
        window = lines[start + 1:start + 61]
        hit = next((i for i, l in enumerate(window) if old in l), None)
        if hit is None:
            if new is not None and sim.is_stock(rel, new) \
                    and old not in sim.stock[rel]:
                return  # earlier simulated call already patched it
            fail(tweak, "patch_line_after_once OLD not within 60 lines after "
                        "the anchor in %s: %s" % (rel, old))
            return
        j = start + 1 + hit
        lines[j] = subst_once(lines[j], old, new or "")
        sim.write(rel, "\n".join(lines))
    elif helper == "sm_add_child":
        service = word(args[1])
        line = word(args[2])
        if service is None:
            warn(tweak, "sm_add_child service not static; skipped")
            return
        needle = 'name="%s"' % service
        if count_lines(text, needle) < 1:
            fail(tweak, "sm_add_child service not found in %s: %s"
                 % (rel, service))
            return
        if line is not None and count_lines(text, line) == 0:
            start = find_line(lines, needle)
            end = next(i for i in range(start, len(lines))
                       if "</service>" in lines[i])
            lines.insert(end, line)
            sim.write(rel, "\n".join(lines))
    elif helper in ("sm_disable_services", "sm_set_attribute", "sm_set_affinity"):
        # FILE alone; +ATTR+VALUE for set_attribute; +MASK for set_affinity.
        start = {"sm_disable_services": 1, "sm_set_attribute": 3,
                 "sm_set_affinity": 2}[helper]
        for tok in args[start:]:
            service = word(tok)
            if service is None:
                warn(tweak, "%s service not static; skipped" % helper)
                continue
            needle = 'name="%s"' % service
            if count_lines(text, needle) < 1:
                # disable skips unknown names at runtime; set_attribute only
                # dies when every requested name is missing, so a stock
                # without the name is not a defect of the tweak.
                warn(tweak, "%s service not in stock %s: %s"
                     % (helper, rel, service))


def check_tweak(tid, root, repo):
    apply_sh = os.path.join(repo, "tweaks", tid, "apply.sh")
    if not os.path.isfile(apply_sh):
        return 0
    tweak_dir = os.path.dirname(apply_sh)
    with open(apply_sh, "r", encoding="utf-8", errors="surrogateescape") as fh:
        text = fh.read()
    commands = split_commands(text)
    variables = collect_assignments(commands, tweak_dir)
    sim = Sim(root)
    count = 0
    for cmd in commands:
        stripped = cmd.strip()
        if not stripped or stripped.startswith("#"):
            continue
        try:
            tokens = tokenize(stripped)
        except ValueError as exc:
            warn(tid, "cannot tokenize: %.60s... (%s)" % (stripped, exc))
            continue
        if not tokens:
            continue
        name = word_value(tokens[0], variables) or ""
        if name not in HELPERS:
            continue
        lo, hi = HELPERS[name]
        if not lo <= len(tokens) - 1 <= hi:
            warn(tid, "unexpected argument count for %s" % name)
            continue
        count += 1
        check_call(tid, sim, name, tokens[1:], tweak_dir, variables)
    return count


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=os.environ.get("OPENCMU_STOCK_ROOT"),
                    help="stock rootfs to check against")
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))), help="repository root")
    args = ap.parse_args()

    if not args.root or not os.path.isdir(args.root):
        sys.stderr.write(
            "check-anchors: no stock root (set OPENCMU_STOCK_ROOT or --root)\n")
        return 2
    root = os.path.abspath(args.root)
    repo = os.path.abspath(args.repo)
    if not os.path.isdir(os.path.join(repo, "tweaks")):
        sys.stderr.write("check-anchors: no tweaks directory in %s\n" % repo)
        return 2

    total = 0
    for tid in sorted(os.listdir(os.path.join(repo, "tweaks"))):
        total += check_tweak(tid, root, repo)

    for line in WARNINGS:
        print("WARN  " + line)
    for line in FAILURES:
        print("FAIL  " + line)
    print("check-anchors: %d calls checked, %d warnings, %d failed"
          % (total, len(WARNINGS), len(FAILURES)))
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
