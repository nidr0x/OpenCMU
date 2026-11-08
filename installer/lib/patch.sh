#!/bin/sh
# OpenCMU patch helpers. Sourced by install.sh and available to tweaks.
#
# Every helper:
#   - refuses a missing or symlinked target,
#   - validates its anchors and aborts before writing when they do not match,
#   - backs the target up once, before the first write,
#   - writes atomically through atomic_write(),
#   - is idempotent, so a second apply does not duplicate a block.
#
# The helpers never guess: an anchor that does not match exactly is an error,
# not a best-effort edit.

_patch_guard() {
  _pg_file=$1
  [ -f "$_pg_file" ] || die "patch target not found: $_pg_file"
  [ -L "$_pg_file" ] && die "refusing to patch symlink: $_pg_file"
  return 0
}

# _count_literal FILE LITERAL -> number of non-overlapping matches, single line
_count_literal() {
  LIT=$2 awk '
    {
      s = $0
      while ((i = index(s, ENVIRON["LIT"])) > 0) {
        c++
        s = substr(s, i + length(ENVIRON["LIT"]))
      }
    }
    END { print c + 0 }
  ' "$1"
}

# patch_subst FILE OLD NEW
# Replaces the single occurrence of the literal OLD with NEW on one line.
patch_subst() {
  ps_file=$1
  ps_old=$2
  ps_new=$3

  _patch_guard "$ps_file"
  case "$ps_old$ps_new" in
    *"
"*) die "patch_subst: OLD and NEW must be single-line" ;;
  esac

  ps_old_hits=$(_count_literal "$ps_file" "$ps_old")
  if [ "$ps_old_hits" -eq 0 ]; then
    if [ "$(_count_literal "$ps_file" "$ps_new")" -gt 0 ]; then
      log "already patched: $ps_file"
      return 0
    fi
    die "patch anchor not found in $ps_file: $ps_old"
  fi
  [ "$ps_old_hits" -eq 1 ] || die "patch anchor matched $ps_old_hits times in $ps_file: $ps_old"

  backup_file "$ps_file" >/dev/null || die "backup failed: $ps_file"

  ps_tmp="$ps_file.opencmu-new.$$"
  OLD=$ps_old NEW=$ps_new awk '
    !done {
      n = index($0, ENVIRON["OLD"])
      if (n > 0) {
        $0 = substr($0, 1, n - 1) ENVIRON["NEW"] substr($0, n + length(ENVIRON["OLD"]))
        done = 1
      }
    }
    { print }
  ' "$ps_file" > "$ps_tmp" || { rm -f "$ps_tmp"; die "patch failed: $ps_file"; }

  atomic_write "$ps_file" "$ps_tmp"
  rm -f "$ps_tmp"
  log "patched $ps_file"
}

# patch_number FILE KEY OLD NEW
# Rewrites the numeric token OLD to NEW on the single line containing KEY.
patch_number() {
  pn_file=$1
  pn_key=$2
  pn_old=$3
  pn_new=$4

  _patch_guard "$pn_file"

  pn_lines=$(grep -cF -- "$pn_key" "$pn_file" || true)
  [ "$pn_lines" -eq 1 ] || die "patch key matched $pn_lines lines in $pn_file: $pn_key"

  if ! grep -F -- "$pn_key" "$pn_file" | grep -qF -- "$pn_old"; then
    if grep -F -- "$pn_key" "$pn_file" | grep -qF -- "$pn_new"; then
      log "already patched: $pn_file ($pn_key)"
      return 0
    fi
    die "patch value not found on '$pn_key' in $pn_file: $pn_old"
  fi

  backup_file "$pn_file" >/dev/null || die "backup failed: $pn_file"

  pn_tmp="$pn_file.opencmu-new.$$"
  KEY=$pn_key OLD=$pn_old NEW=$pn_new awk '
    !done && index($0, ENVIRON["KEY"]) > 0 {
      n = index($0, ENVIRON["OLD"])
      if (n > 0) {
        $0 = substr($0, 1, n - 1) ENVIRON["NEW"] substr($0, n + length(ENVIRON["OLD"]))
        done = 1
      }
    }
    { print }
  ' "$pn_file" > "$pn_tmp" || { rm -f "$pn_tmp"; die "patch failed: $pn_file"; }

  atomic_write "$pn_file" "$pn_tmp"
  rm -f "$pn_tmp"
  log "patched $pn_file ($pn_key)"
}

# patch_quoted_value FILE KEY NEWVALUE
# Replaces the quoted value that follows KEY on its line, keeping the key and
# the surrounding punctuation. Used for JSON-style app dictionaries.
patch_quoted_value() {
  pq_file=$1
  pq_key=$2
  pq_new=$3

  _patch_guard "$pq_file"

  pq_lines=$(grep -cF -- "$pq_key" "$pq_file" || true)
  [ "$pq_lines" -eq 1 ] || die "patch key matched $pq_lines lines in $pq_file: $pq_key"

  if grep -F -- "$pq_key" "$pq_file" | grep -qF -- "\"$pq_new\""; then
    log "already patched: $pq_file ($pq_key)"
    return 0
  fi

  backup_file "$pq_file" >/dev/null || die "backup failed: $pq_file"

  pq_tmp="$pq_file.opencmu-new.$$"
  KEY=$pq_key NEW=$pq_new awk '
    {
      if (!done && index($0, ENVIRON["KEY"]) > 0) {
        k = index($0, ENVIRON["KEY"])
        rest = substr($0, k + length(ENVIRON["KEY"]))
        c = index(rest, ":")
        if (c > 0) {
          after = substr(rest, c + 1)
          q1 = index(after, "\"")
          if (q1 > 0) {
            tail = substr(after, q1 + 1)
            q2 = index(tail, "\"")
            if (q2 > 0) {
              $0 = substr($0, 1, k + length(ENVIRON["KEY"]) + c + q1 - 1) \
                   ENVIRON["NEW"] substr(after, q1 + q2)
              done = 1
            }
          }
        }
      }
      print
    }
    END { if (!done) exit 3 }
  ' "$pq_file" > "$pq_tmp" || { rm -f "$pq_tmp"; die "no quoted value found for $pq_key in $pq_file"; }

  atomic_write "$pq_file" "$pq_tmp"
  rm -f "$pq_tmp"
  log "patched $pq_file ($pq_key)"
}

# append_once FILE MARKER BLOCK_FILE
# Appends BLOCK_FILE to FILE unless MARKER is already present.
append_once() {
  ap_file=$1
  ap_marker=$2
  ap_block=$3

  _patch_guard "$ap_file"
  [ -f "$ap_block" ] || die "patch block not found: $ap_block"

  if grep -qF -- "$ap_marker" "$ap_file"; then
    log "already patched: $ap_file ($ap_marker)"
    return 0
  fi

  backup_file "$ap_file" >/dev/null || die "backup failed: $ap_file"

  ap_tmp="$ap_file.opencmu-new.$$"
  { cat "$ap_file"; printf '\n'; cat "$ap_block"; } > "$ap_tmp" ||
    { rm -f "$ap_tmp"; die "patch failed: $ap_file"; }

  atomic_write "$ap_file" "$ap_tmp"
  rm -f "$ap_tmp"
  log "appended $ap_marker to $ap_file"
}

# prepend_once FILE MARKER BLOCK_FILE
# Puts BLOCK_FILE at the top of FILE unless MARKER is already present. Used for
# configs where the first value of a keyword wins, such as sshd_config.
prepend_once() {
  pp_file=$1
  pp_marker=$2
  pp_block=$3

  _patch_guard "$pp_file"
  [ -f "$pp_block" ] || die "patch block not found: $pp_block"

  if grep -qF -- "$pp_marker" "$pp_file"; then
    log "already patched: $pp_file ($pp_marker)"
    return 0
  fi

  backup_file "$pp_file" >/dev/null || die "backup failed: $pp_file"

  pp_tmp="$pp_file.opencmu-new.$$"
  { cat "$pp_block"; printf '\n'; cat "$pp_file"; } > "$pp_tmp" ||
    { rm -f "$pp_tmp"; die "patch failed: $pp_file"; }

  atomic_write "$pp_file" "$pp_tmp"
  rm -f "$pp_tmp"
  log "prepended $pp_marker to $pp_file"
}

# insert_before_once FILE MARKER ANCHOR BLOCK_FILE
# Inserts BLOCK_FILE before the single line containing ANCHOR.
insert_before_once() {
  ib_file=$1
  ib_marker=$2
  ib_anchor=$3
  ib_block=$4

  _patch_guard "$ib_file"
  [ -f "$ib_block" ] || die "patch block not found: $ib_block"

  if grep -qF -- "$ib_marker" "$ib_file"; then
    log "already patched: $ib_file ($ib_marker)"
    return 0
  fi

  ib_lines=$(grep -cF -- "$ib_anchor" "$ib_file" || true)
  [ "$ib_lines" -eq 1 ] || die "insert anchor matched $ib_lines lines in $ib_file: $ib_anchor"

  backup_file "$ib_file" >/dev/null || die "backup failed: $ib_file"

  ib_tmp="$ib_file.opencmu-new.$$"
  awk -v anchor="$ib_anchor" -v block="$ib_block" '
    BEGIN { while ((getline l < block) > 0) b = b l "\n" }
    !done && index($0, anchor) > 0 { printf "%s", b; done = 1 }
    { print }
  ' "$ib_file" > "$ib_tmp" || { rm -f "$ib_tmp"; die "patch failed: $ib_file"; }

  atomic_write "$ib_file" "$ib_tmp"
  rm -f "$ib_tmp"
  log "inserted $ib_marker into $ib_file"
}

# patch_subst_all FILE OLD NEW MIN
# Replaces every occurrence of the single-line literal OLD with NEW.
# MIN is the number of occurrences that must be present before anything is
# written; it defaults to 1. Used where the stock file repeats the same line
# on purpose (for example three boot stages waiting on the same service).
patch_subst_all() {
  pa_file=$1
  pa_old=$2
  pa_new=$3
  pa_min=${4:-1}

  _patch_guard "$pa_file"
  case "$pa_old$pa_new" in
    *"
"*) die "patch_subst_all: OLD and NEW must be single-line" ;;
  esac
  case "$pa_min" in
    ''|*[!0-9]*) die "patch_subst_all: MIN must be a number" ;;
  esac

  pa_hits=$(_count_literal "$pa_file" "$pa_old")
  if [ "$pa_hits" -eq 0 ]; then
    if [ "$(_count_literal "$pa_file" "$pa_new")" -gt 0 ]; then
      log "already patched: $pa_file"
      return 0
    fi
    die "patch anchor not found in $pa_file: $pa_old"
  fi
  [ "$pa_hits" -ge "$pa_min" ] ||
    die "patch anchor matched $pa_hits times in $pa_file, expected at least $pa_min: $pa_old"

  backup_file "$pa_file" >/dev/null || die "backup failed: $pa_file"

  pa_tmp="$pa_file.opencmu-new.$$"
  OLD=$pa_old NEW=$pa_new awk '
    {
      s = $0
      out = ""
      n = 0
      while ((i = index(s, ENVIRON["OLD"])) > 0) {
        out = out substr(s, 1, i - 1) ENVIRON["NEW"]
        s = substr(s, i + length(ENVIRON["OLD"]))
        n++
      }
      if (n > 0) $0 = out s
      print
    }
  ' "$pa_file" > "$pa_tmp" || { rm -f "$pa_tmp"; die "patch failed: $pa_file"; }

  atomic_write "$pa_file" "$pa_tmp"
  rm -f "$pa_tmp"
  log "patched $pa_file ($pa_hits occurrences)"
}

# sm_disable_services FILE SERVICE...
# Sets autorun="no" inside the <service ...> block of each named service in a
# Service Manager config. Services that this firmware does not define are
# reported and skipped: service sets differ between regions. The file is
# written once, and only if every requested service was located and validated,
# so a wrong service name cannot leave a half-edited sm.conf behind.
sm_disable_services() {
  sd_file=$1
  shift
  [ $# -gt 0 ] || die "sm_disable_services: no service name given"

  _patch_guard "$sd_file"
  for sd_name in "$@"; do
    case "$sd_name" in
      *[!A-Za-z0-9._-]*) die "sm_disable_services: invalid service name: $sd_name" ;;
    esac
  done

  sd_names="$sd_file.opencmu-names.$$"
  sd_tmp="$sd_file.opencmu-new.$$"
  printf '%s\n' "$@" > "$sd_names"

  if NAMES="$sd_names" awk '
    BEGIN {
      while ((getline n < ENVIRON["NAMES"]) > 0) {
        if (n != "") { want[n] = 1; total++ }
      }
    }
    {
      line = $0
      opened = 0
      if (!inblock && index($0, "<service ") > 0) {
        inblock = 1
        opened = 1
        current = ""
        for (w in want) {
          if (index($0, "name=\"" w "\"") > 0) { current = w; seen[w] = 1 }
        }
      }
      if (inblock && current != "") {
        p = index(line, "autorun=\"yes\"")
        if (p > 0) {
          line = substr(line, 1, p - 1) "autorun=\"no\"" substr(line, p + 13)
          changes++
          disabled[current] = 1
        } else if (opened) {
          if (index(line, "autorun=\"") > 0) {
            disabled[current] = 1
          } else {
            tag = index(line, "<service")
            gt = index(substr(line, tag), ">")
            if (gt > 0) {
              pos = tag + gt - 1
              line = substr(line, 1, pos - 1) " autorun=\"no\"" substr(line, pos)
              changes++
              disabled[current] = 1
            }
          }
        }
      }
      if (inblock && index($0, "</service>") > 0) { inblock = 0; current = "" }
      print line
    }
    END {
      missing = 0
      for (w in want) {
        if (!(w in seen)) { print "MISSING " w > "/dev/stderr"; missing++ }
        else if (!(w in disabled))
          print "NO-AUTORUN " w > "/dev/stderr"
      }
      if (missing == total) exit 3
      if (changes == 0) exit 4
    }
  ' "$sd_file" > "$sd_tmp"; then
    sd_rc=0
  else
    sd_rc=$?
  fi
  rm -f "$sd_names"

  case "$sd_rc" in
    0) : ;;
    4)
      rm -f "$sd_tmp"
      log "already patched: $sd_file"
      return 0
      ;;
    3)
      rm -f "$sd_tmp"
      die "no requested service found in $sd_file"
      ;;
    *)
      rm -f "$sd_tmp"
      die "service patch failed: $sd_file"
      ;;
  esac

  backup_file "$sd_file" >/dev/null || { rm -f "$sd_tmp"; die "backup failed: $sd_file"; }
  atomic_write "$sd_file" "$sd_tmp"
  rm -f "$sd_tmp"
  log "disabled services in $sd_file: $*"
}

# patch_key_value FILE KEY VALUE
# Rewrites the value after "KEY =" on its single line, whatever the old value
# was. Used for configuration files whose stock value differs between builds,
# so the tweak does not have to know it.
patch_key_value() {
  pv_file=$1
  pv_key=$2
  pv_new=$3

  _patch_guard "$pv_file"
  case "$pv_new" in
    *"
"*) die "patch_key_value: VALUE must be single-line" ;;
  esac

  pv_lines=$(grep -cF -- "$pv_key" "$pv_file" || true)
  [ "$pv_lines" -eq 1 ] || die "patch key matched $pv_lines lines in $pv_file: $pv_key"

  pv_tmp="$pv_file.opencmu-new.$$"
  if ! KEY=$pv_key NEW=$pv_new awk '
    !done && index($0, ENVIRON["KEY"]) > 0 {
      k = index($0, ENVIRON["KEY"])
      rest = substr($0, k + length(ENVIRON["KEY"]))
      eq = index(rest, "=")
      if (eq > 0) {
        $0 = substr($0, 1, k + length(ENVIRON["KEY"]) + eq - 1) " " ENVIRON["NEW"]
        done = 1
      }
    }
    { print }
    END { if (!done) exit 3 }
  ' "$pv_file" > "$pv_tmp"; then
    rm -f "$pv_tmp"
    die "no value to rewrite for $pv_key in $pv_file"
  fi

  if cmp -s "$pv_file" "$pv_tmp"; then
    rm -f "$pv_tmp"
    log "already patched: $pv_file ($pv_key)"
    return 0
  fi

  backup_file "$pv_file" >/dev/null || { rm -f "$pv_tmp"; die "backup failed: $pv_file"; }
  atomic_write "$pv_file" "$pv_tmp"
  rm -f "$pv_tmp"
  log "patched $pv_file ($pv_key)"
}

# sm_set_attribute FILE ATTR VALUE SERVICE...
# Sets one attribute on the opening <service> tag of each named service in the
# Service Manager config. An existing attribute is rewritten; a missing one is
# added. The file is written once, and only after every requested service was
# located, so a partial edit never reaches the unit.
sm_set_attribute() {
  sa_file=$1
  sa_attr=$2
  sa_value=$3
  shift 3
  [ $# -gt 0 ] || die "sm_set_attribute: no service name given"

  _patch_guard "$sa_file"
  case "$sa_attr" in
    ''|*[!A-Za-z0-9_]*) die "sm_set_attribute: invalid attribute: $sa_attr" ;;
  esac
  case "$sa_value" in
    ''|*[!A-Za-z0-9._/:-]*) die "sm_set_attribute: invalid value: $sa_value" ;;
  esac
  for sa_name in "$@"; do
    case "$sa_name" in
      *[!A-Za-z0-9._-]*) die "sm_set_attribute: invalid service name: $sa_name" ;;
    esac
  done

  sa_names="$sa_file.opencmu-attr.$$"
  sa_tmp="$sa_file.opencmu-new.$$"
  printf '%s\n' "$@" > "$sa_names"

  if NAMES="$sa_names" ATTR="$sa_attr" VALUE="$sa_value" awk '
    BEGIN {
      while ((getline n < ENVIRON["NAMES"]) > 0) {
        if (n != "") { want[n] = 1; total++ }
      }
      attr = ENVIRON["ATTR"]
      value = ENVIRON["VALUE"]
      needle = attr "=\""
    }
    {
      line = $0
      opened = 0
      if (!inblock && index($0, "<service ") > 0) {
        inblock = 1
        opened = 1
        current = ""
        for (w in want) {
          if (index($0, "name=\"" w "\"") > 0) { current = w; seen[w] = 1 }
        }
      }
      if (inblock && current != "" && opened) {
        p = index(line, needle)
        if (p > 0) {
          rest = substr(line, p + length(needle))
          q = index(rest, "\"")
          if (q <= 0) {
            bad[current] = 1
          } else if (substr(rest, 1, q - 1) == value) {
            ok[current] = 1
          } else {
            line = substr(line, 1, p + length(needle) - 1) value substr(rest, q)
            changes++
            ok[current] = 1
          }
        } else {
          tag = index(line, "<service")
          gt = index(substr(line, tag), ">")
          if (gt <= 0) {
            bad[current] = 1
          } else {
            pos = tag + gt - 1
            line = substr(line, 1, pos - 1) " " attr "=\"" value "\"" substr(line, pos)
            changes++
            ok[current] = 1
          }
        }
      }
      if (inblock && index($0, "</service>") > 0) { inblock = 0; current = "" }
      print line
    }
    END {
      missing = 0
      for (w in want) {
        if (!(w in seen)) { print "MISSING " w > "/dev/stderr"; missing++ }
        else if (w in bad) { print "NO-TAG-END " w > "/dev/stderr"; badcount++ }
        else if (!(w in ok)) { print "NOT-SET " w > "/dev/stderr"; badcount++ }
      }
      if (missing == total) exit 3
      if (badcount > 0) exit 5
      if (changes == 0) exit 4
    }
  ' "$sa_file" > "$sa_tmp"; then
    sa_rc=0
  else
    sa_rc=$?
  fi
  rm -f "$sa_names"

  case "$sa_rc" in
    0) : ;;
    4)
      rm -f "$sa_tmp"
      log "already patched: $sa_file ($sa_attr)"
      return 0
      ;;
    3)
      rm -f "$sa_tmp"
      die "no requested service found in $sa_file"
      ;;
    5)
      rm -f "$sa_tmp"
      die "could not set $sa_attr on every requested service in $sa_file"
      ;;
    *)
      rm -f "$sa_tmp"
      die "attribute patch failed: $sa_file"
      ;;
  esac

  backup_file "$sa_file" >/dev/null || { rm -f "$sa_tmp"; die "backup failed: $sa_file"; }
  atomic_write "$sa_file" "$sa_tmp"
  rm -f "$sa_tmp"
  log "set $sa_attr=\"$sa_value\" in $sa_file: $*"
}

# sm_set_affinity FILE MASK SERVICE...
# Pins named services to a CPU affinity mask. Thin wrapper over
# sm_set_attribute, kept because the tweak reads better that way.
sm_set_affinity() {
  sa_file=$1
  sa_mask=$2
  shift 2
  sm_set_attribute "$sa_file" affinity_mask "$sa_mask" "$@"
}

# sm_add_child FILE SERVICE LINE
# Inserts one line before the closing </service> of the named service, once.
# Used for service children such as <environ_var>, which have no stable anchor
# of their own. Idempotent: the line is skipped when it is already present.
sm_add_child() {
  sc_file=$1
  sc_service=$2
  sc_line=$3

  _patch_guard "$sc_file"
  case "$sc_service" in
    ''|*[!A-Za-z0-9._-]*) die "sm_add_child: invalid service name: $sc_service" ;;
  esac
  case "$sc_line" in
    *"
"*) die "sm_add_child: LINE must be single-line" ;;
  esac

  if grep -qF -- "$sc_line" "$sc_file"; then
    log "already patched: $sc_file ($sc_service)"
    return 0
  fi

  sc_tmp="$sc_file.opencmu-new.$$"
  if SERVICE="$sc_service" LINE="$sc_line" awk '
    BEGIN { service = ENVIRON["SERVICE"]; line = ENVIRON["LINE"] }
    {
      if (!inblock && index($0, "<service ") > 0 && index($0, "name=\"" service "\"") > 0) {
        inblock = 1
        found = 1
      }
      if (inblock && index($0, "</service>") > 0) {
        print line
        inblock = 0
        inserted = 1
      }
      print
    }
    END {
      if (!found) exit 3
      if (!inserted) exit 4
    }
  ' "$sc_file" > "$sc_tmp"; then
    sc_rc=0
  else
    sc_rc=$?
  fi

  case "$sc_rc" in
    0) : ;;
    3)
      rm -f "$sc_tmp"
      die "service not found in $sc_file: $sc_service"
      ;;
    4)
      rm -f "$sc_tmp"
      die "service block not closed in $sc_file: $sc_service"
      ;;
    *)
      rm -f "$sc_tmp"
      die "child patch failed: $sc_file"
      ;;
  esac

  backup_file "$sc_file" >/dev/null || { rm -f "$sc_tmp"; die "backup failed: $sc_file"; }
  atomic_write "$sc_file" "$sc_tmp"
  rm -f "$sc_tmp"
  log "added child to $sc_service in $sc_file"
}

# patch_line_after_once FILE ANCHOR OLD NEW [MARKER]
# Replaces OLD with NEW on the first line after the single line containing
# ANCHOR, within the next 60 lines. Used when the literal to change appears
# several times in a file but only one occurrence follows a unique anchor.
# NEW may span lines, so the idempotency check uses MARKER when given; pass a
# marker whenever NEW contains a newline.
patch_line_after_once() {
  pl_file=$1
  pl_anchor=$2
  pl_old=$3
  pl_new=$4
  pl_marker=${5:-}

  _patch_guard "$pl_file"
  case "$pl_old" in
    *"
"*) die "patch_line_after_once: OLD must be single-line" ;;
  esac

  if [ -n "$pl_marker" ]; then
    if grep -qF -- "$pl_marker" "$pl_file"; then
      log "already patched: $pl_file"
      return 0
    fi
  else
    case "$pl_new" in
      *"
"*) die "patch_line_after_once: a marker is required when NEW spans lines" ;;
    esac
    if grep -qF -- "$pl_new" "$pl_file"; then
      log "already patched: $pl_file"
      return 0
    fi
  fi

  pl_lines=$(grep -cF -- "$pl_anchor" "$pl_file" || true)
  [ "$pl_lines" -eq 1 ] || die "anchor matched $pl_lines lines in $pl_file: $pl_anchor"

  pl_tmp="$pl_file.opencmu-new.$$"
  if ! ANCHOR=$pl_anchor OLD=$pl_old NEW=$pl_new awk '
    !done && index($0, ENVIRON["ANCHOR"]) > 0 { armed = 1; n = 0 }
    {
      if (armed && !done && index($0, ENVIRON["OLD"]) > 0) {
        i = index($0, ENVIRON["OLD"])
        $0 = substr($0, 1, i - 1) ENVIRON["NEW"] substr($0, i + length(ENVIRON["OLD"]))
        done = 1
      }
      if (armed && !done) {
        n++
        if (n > 60) armed = 0
      }
      print
    }
    END { if (!done) exit 3 }
  ' "$pl_file" > "$pl_tmp"; then
    rm -f "$pl_tmp"
    die "no line to patch after '$pl_anchor' in $pl_file: $pl_old"
  fi

  if cmp -s "$pl_file" "$pl_tmp"; then
    rm -f "$pl_tmp"
    log "already patched: $pl_file"
    return 0
  fi

  backup_file "$pl_file" >/dev/null || { rm -f "$pl_tmp"; die "backup failed: $pl_file"; }
  atomic_write "$pl_file" "$pl_tmp"
  rm -f "$pl_tmp"
  log "patched $pl_file after '$pl_anchor'"
}

# insert_after_once FILE MARKER ANCHOR BLOCK
# Inserts BLOCK after the single line containing ANCHOR, once. The mirror of
# insert_before_once, for anchors that open a block (a function header, a case
# label) instead of closing one.
insert_after_once() {
  ia_file=$1
  ia_marker=$2
  ia_anchor=$3
  ia_block=$4

  _patch_guard "$ia_file"
  [ -f "$ia_block" ] || die "patch block not found: $ia_block"

  if grep -qF -- "$ia_marker" "$ia_file"; then
    log "already patched: $ia_file ($ia_marker)"
    return 0
  fi

  ia_lines=$(grep -cF -- "$ia_anchor" "$ia_file" || true)
  [ "$ia_lines" -eq 1 ] || die "insert anchor matched $ia_lines lines in $ia_file: $ia_anchor"

  backup_file "$ia_file" >/dev/null || die "backup failed: $ia_file"

  ia_tmp="$ia_file.opencmu-new.$$"
  awk -v anchor="$ia_anchor" -v block="$ia_block" '
    BEGIN { while ((getline l < block) > 0) b = b l "\n" }
    { print }
    !done && index($0, anchor) > 0 { printf "%s", b; done = 1 }
  ' "$ia_file" > "$ia_tmp" || { rm -f "$ia_tmp"; die "patch failed: $ia_file"; }

  atomic_write "$ia_file" "$ia_tmp"
  rm -f "$ia_tmp"
  log "inserted $ia_marker after the anchor in $ia_file"
}
