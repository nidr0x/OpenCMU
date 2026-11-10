#!/bin/sh
# shellcheck disable=SC1090,SC1091
# OpenCMU smoke test. Runs the installer against a temporary fake root.
# Never touches a real CMU or the repository's tracked files.
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/opencmu-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM

FAKE="$TMP/root"
PAYLOAD="$TMP/payload"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$*"
}

make_root() {
  root=$1
  mkdir -p "$root/jci"
  printf '[Info]\nJCI_SW_VER=74.00.324\n' > "$root/jci/version.ini"
}

hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

mkdir -p "$PAYLOAD/lib"
cp "$ROOT_DIR/installer/install.sh" "$PAYLOAD/"
cp "$ROOT_DIR"/installer/lib/*.sh "$PAYLOAD/lib/"
cp "$ROOT_DIR/manifest.env" "$PAYLOAD/"
cp -R "$ROOT_DIR/tweaks" "$PAYLOAD/tweaks"
make_root "$FAKE"

# Test-only tweaks: one succeeds, one writes a file and then fails.
mkdir -p "$PAYLOAD/tweaks/60-test" "$PAYLOAD/tweaks/70-fail"
cat > "$PAYLOAD/tweaks/60-test/tweak.env" <<'EOF'
TWEAK_NAME="Test tweak 60"
TWEAK_RISK="low"
EOF
cat > "$PAYLOAD/tweaks/60-test/apply.sh" <<'EOF'
target="$OPENCMU_ROOT/data/opencmu/test-60.txt"
record_created "$target"
backup_file "$target" >/dev/null || die "backup failed"
printf 'test-60\n' > "$target"
log "wrote $target"
EOF
cat > "$PAYLOAD/tweaks/60-test/rollback.sh" <<'EOF'
rollback_path "$OPENCMU_ROOT/data/opencmu/test-60.txt"
EOF
cat > "$PAYLOAD/tweaks/70-fail/tweak.env" <<'EOF'
TWEAK_NAME="Test tweak 70"
TWEAK_RISK="low"
EOF
cat > "$PAYLOAD/tweaks/70-fail/apply.sh" <<'EOF'
target="$OPENCMU_ROOT/data/opencmu/test-70.txt"
record_created "$target"
backup_file "$target" >/dev/null || die "backup failed"
printf 'test-70\n' > "$target"
die "intentional failure after writing"
EOF
cat > "$PAYLOAD/tweaks/70-fail/rollback.sh" <<'EOF'
rollback_path "$OPENCMU_ROOT/data/opencmu/test-70.txt"
EOF

run() {
  sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE" "$@"
}

# 1. Dry run plans the tweak and writes nothing.
out=$(run)
printf '%s\n' "$out" | grep -q 'would apply: 00-example' || fail "dry run did not plan 00-example"
[ ! -e "$FAKE/data/opencmu/example-marker.txt" ] || fail "dry run wrote the marker"
[ ! -d "$FAKE/data/opencmu/state" ] || fail "dry run created the state directory"
pass "dry run writes nothing"

# 2. Apply creates the marker, the receipt, and the backup.
run --apply >/dev/null
MARKER="$FAKE/data/opencmu/example-marker.txt"
RECEIPT="$FAKE/data/opencmu/state/receipt.env"
[ -f "$MARKER" ] || fail "apply did not create the marker"
[ -f "$RECEIPT" ] || fail "apply did not write the receipt"
. "$RECEIPT"
[ "$TWEAKS" = "00-example" ] || fail "receipt has wrong tweak list: $TWEAKS"
[ -d "$BACKUP_DIR" ] || fail "backup directory missing: $BACKUP_DIR"
pass "apply writes marker, receipt, and backup"

# 2b. A second apply is refused until the first install is rolled back.
if run --apply >/dev/null 2>&1; then
  fail "installer allowed a second apply without rollback"
fi
pass "second apply requires rollback"

# 3. Rollback is a dry run by default.
out=$(run --rollback)
printf '%s\n' "$out" | grep -q 'dry-run' || fail "rollback dry run not reported"
[ -f "$MARKER" ] || fail "rollback dry run removed the marker"
pass "rollback dry run keeps files"

# 4. Rollback with --apply removes the created marker and clears the receipt.
run --apply --rollback >/dev/null
[ ! -e "$MARKER" ] || fail "rollback left the marker"
[ ! -f "$RECEIPT" ] || fail "rollback left the receipt"
pass "rollback restores the fake root"

# 4b. Hashing falls back to openssl: the unit has no sha256sum or shasum.
if command -v openssl >/dev/null 2>&1 && [ -x /bin/sh ]; then
  ONLY="$TMP/bin-openssl"
  mkdir -p "$ONLY"
  ln -s "$(command -v openssl)" "$ONLY/openssl"
  ln -s "$(command -v awk)" "$ONLY/awk"
  openssl_hash=$(PATH="$ONLY" /bin/sh -c \
    ". '$ROOT_DIR/installer/lib/common.sh'; sha256_file '$ROOT_DIR/README.md'")
  [ "$openssl_hash" = "$(hash "$ROOT_DIR/README.md")" ] ||
    fail "sha256_file does not fall back to openssl"
  pass "hashing works without sha256sum"
fi

# 5. Firmware guard rejects old and new versions.
printf '[Info]\nJCI_SW_VER=73.00.000\n' > "$FAKE/jci/version.ini"
if run --apply >/dev/null 2>&1; then
  fail "installer accepted firmware 73.00.000"
fi
printf '[Info]\nJCI_SW_VER=75.00.001\n' > "$FAKE/jci/version.ini"
if run --apply >/dev/null 2>&1; then
  fail "installer accepted firmware 75.00.001"
fi
printf '[Info]\nJCI_SW_VER=74.00.331\n' > "$FAKE/jci/version.ini"
if run --apply >/dev/null 2>&1; then
  fail "installer accepted firmware 74.00.331"
fi
printf '[Info]\nJCI_SW_VER=74.00.324\n' > "$FAKE/jci/version.ini"
pass "firmware guard rejects versions outside the range"

# 5b. The real 74.00.324 version.ini carries a build prefix and quotes:
# JCI_SW_VER="MAZ_CMU-150_74.00.324". Only the numeric part may be compared.
printf '[VersionInfo]\nJCI_SW_VER="MAZ_CMU-150_74.00.324"\n' > "$FAKE/jci/version.ini"
out=$(run)
printf '%s\n' "$out" | grep -q 'firmware: 74.00.324' ||
  fail "stock version format was not normalized to its numeric part"
printf '[Info]\nJCI_SW_VER=74.00.324\n' > "$FAKE/jci/version.ini"
pass "stock version format is normalized"

# 6. Missing version.ini is fatal unless --force is passed.
mv "$FAKE/jci/version.ini" "$FAKE/jci/version.ini.bak"
if run --apply >/dev/null 2>&1; then
  fail "installer accepted a missing version.ini"
fi
mv "$FAKE/jci/version.ini.bak" "$FAKE/jci/version.ini"
pass "missing version.ini is fatal"

# 7. Experimental tweaks need --experimental and must not create state on failure.
FAKE2="$TMP/root2"
make_root "$FAKE2"
if sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE2" --apply --tweaks 90-replacement-template >/dev/null 2>&1; then
  fail "experimental tweak ran without --experimental"
fi
[ ! -d "$FAKE2/data/opencmu/state" ] || fail "failed preflight created state"
pass "experimental gating fails before writing"

# 8. Hash-verified replacement and rollback (experimental template).
FAKE3="$TMP/root3"
make_root "$FAKE3"
mkdir -p "$FAKE3/opt/opencmu-test"
TARGET="$FAKE3/opt/opencmu-test/sample.txt"
REPL="$TMP/sample.patched"
printf 'stock\n' > "$TARGET"
printf 'patched\n' > "$REPL"
STOCK_HASH=$(hash "$TARGET")

cat > "$PAYLOAD/tweaks/90-replacement-template/tweak.local.env" <<EOF
TARGET_FILE=$TARGET
REPLACEMENT_FILE=$REPL
EXPECTED_SHA256=$STOCK_HASH
EOF

sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE3" --apply --experimental --tweaks 90-replacement-template >/dev/null
[ "$(cat "$TARGET")" = "patched" ] || fail "replacement was not installed"
sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE3" --apply --rollback >/dev/null
[ "$(cat "$TARGET")" = "stock" ] || fail "replacement was not rolled back"
pass "hash-verified replacement rolls back"

# 9. A wrong expected hash aborts and leaves the target untouched.
cat > "$PAYLOAD/tweaks/90-replacement-template/tweak.local.env" <<EOF
TARGET_FILE=$TARGET
REPLACEMENT_FILE=$REPL
EXPECTED_SHA256=0000000000000000000000000000000000000000000000000000000000000000
EOF
if sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE3" --apply --experimental --tweaks 90-replacement-template >/dev/null 2>&1; then
  fail "installer accepted a wrong expected hash"
fi
[ "$(cat "$TARGET")" = "stock" ] || fail "wrong hash still changed the target"
sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE3" --apply --rollback >/dev/null
[ ! -f "$FAKE3/data/opencmu/state/receipt.env" ] || fail "rollback left the receipt after a failed apply"
rm -f "$PAYLOAD/tweaks/90-replacement-template/tweak.local.env"
pass "wrong hash aborts without writing"

# 10. Multi-tweak plan: quoted receipt and reverse-order rollback.
FAKE4="$TMP/root4"
make_root "$FAKE4"
run4() {
  sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE4" "$@"
}
run4 --apply --tweaks "00-example 60-test" >/dev/null
[ -f "$FAKE4/data/opencmu/example-marker.txt" ] || fail "multi-tweak: 00-example missing"
[ -f "$FAKE4/data/opencmu/test-60.txt" ] || fail "multi-tweak: 60-test missing"
. "$FAKE4/data/opencmu/state/receipt.env"
[ "$TWEAKS" = "00-example 60-test" ] || fail "multi-tweak receipt: $TWEAKS"
run4 --apply --rollback >/dev/null
[ ! -e "$FAKE4/data/opencmu/example-marker.txt" ] || fail "multi-tweak rollback left 00-example"
[ ! -e "$FAKE4/data/opencmu/test-60.txt" ] || fail "multi-tweak rollback left 60-test"
[ ! -f "$FAKE4/data/opencmu/state/receipt.env" ] || fail "multi-tweak rollback left the receipt"
pass "multi-tweak install and rollback"

# 11. A failing tweak is journaled and its partial writes are rolled back.
FAKE5="$TMP/root5"
make_root "$FAKE5"
run5() {
  sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE5" "$@"
}
if run5 --apply --tweaks "00-example 70-fail" >/dev/null 2>&1; then
  fail "failing tweak reported success"
fi
[ -f "$FAKE5/data/opencmu/example-marker.txt" ] || fail "partial: first tweak was not applied"
[ -f "$FAKE5/data/opencmu/test-70.txt" ] || fail "partial: failing tweak did not write before failing"
[ -f "$FAKE5/data/opencmu/state/receipt.env" ] || fail "partial: receipt was lost"
grep -qx '70-fail' "$FAKE5/data/opencmu/state/installed.list" || fail "partial: failing tweak was not journaled"
run5 --apply --rollback >/dev/null
[ ! -e "$FAKE5/data/opencmu/example-marker.txt" ] || fail "partial rollback left 00-example"
[ ! -e "$FAKE5/data/opencmu/test-70.txt" ] || fail "partial rollback left 70-fail"
[ ! -f "$FAKE5/data/opencmu/state/receipt.env" ] || fail "partial rollback left the receipt"
pass "partial install is journaled and rolled back"

# 11b. An empty journal with a non-empty backup is not cleared blindly.
FAKE6="$TMP/root6"
make_root "$FAKE6"
run6() {
  sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE6" "$@"
}
run6 --apply >/dev/null
: > "$FAKE6/data/opencmu/state/installed.list"
if run6 --apply --rollback >/dev/null 2>&1; then
  fail "rollback cleared the receipt with an empty journal and a non-empty backup"
fi
[ -f "$FAKE6/data/opencmu/state/receipt.env" ] || fail "rollback dropped the receipt in the ambiguous case"
[ -f "$FAKE6/data/opencmu/example-marker.txt" ] || fail "ambiguous rollback still changed files"
printf '00-example\n' > "$FAKE6/data/opencmu/state/installed.list"
run6 --apply --rollback >/dev/null
[ ! -e "$FAKE6/data/opencmu/example-marker.txt" ] || fail "repaired journal did not roll back"
pass "ambiguous rollback refuses and can be repaired"

# 12. --list shows bundled and experimental tweaks.
out=$(run --list)
printf '%s\n' "$out" | grep -q '00-example' || fail "--list omitted 00-example"
printf '%s\n' "$out" | grep -q '90-replacement-template' || fail "--list omitted 90-replacement-template"
pass "--list shows tweaks"

# 13. Builder, extra-file detection, and reproducible .up output.
if command -v python3 >/dev/null 2>&1; then
  sh "$ROOT_DIR/builder/build-usb.sh" "$TMP/usb" >/dev/null
  sh "$ROOT_DIR/builder/verify-usb.sh" "$TMP/usb" >/dev/null
  [ -f "$TMP/usb/install.sh" ] || fail "USB build missing install.sh"
  [ -f "$TMP/usb/SHA256SUMS" ] || fail "USB build missing SHA256SUMS"
  [ -f "$TMP/usb/jci-autoupdate" ] || fail "USB build missing jci-autoupdate"

  printf 'extra\n' > "$TMP/usb/extra.txt"
  if sh "$ROOT_DIR/builder/verify-usb.sh" "$TMP/usb" >/dev/null 2>&1; then
    fail "verify-usb accepted an unlisted file"
  fi
  rm -f "$TMP/usb/extra.txt"

  python3 "$ROOT_DIR/builder/make-up.py" --out "$TMP/a.up" --force >/dev/null 2>&1
  python3 "$ROOT_DIR/builder/make-up.py" --out "$TMP/b.up" --force >/dev/null 2>&1
  cmp -s "$TMP/a.up" "$TMP/b.up" || fail ".up build is not reproducible"

  python3 - "$TMP/a.up" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as zf:
    names = sorted(zf.namelist())
    assert names == ["main_instructions.ini", "versions.ini"], names
    main = zf.read("main_instructions.ini").decode()
    versions = zf.read("versions.ini").decode()
    assert 'Execute, "bootstrap", "execute.ini", 1' in main
    assert "JCI_SW_VER" in versions
PY
  pass "USB payload, extra-file check, and reproducible .up"
fi

# 14. Firmware text patches: apply, idempotency, and rollback.
FAKE7="$TMP/root7"
make_root "$FAKE7"
mkdir -p "$FAKE7/jci/gui/apps/system/js" \
         "$FAKE7/jci/gui/apps/system/controls/MainMenu/js" \
         "$FAKE7/jci/gui/common/controls/List2/js" \
         "$FAKE7/jci/gui/common/controls/NowPlaying4/js" \
         "$FAKE7/jci/gui/common/controls/NowPlaying4/css" \
         "$FAKE7/jci/gui/common/controls/Ump3/css" \
         "$FAKE7/jci/gui/common/js" \
         "$FAKE7/jci/gui/apps/usbaudio/js" \
         "$FAKE7/jci/gui/apps/btaudio/js" \
         "$FAKE7/jci/gui/apps/carplay/js" \
         "$FAKE7/jci/gui/resources/js/backupparking" \
         "$FAKE7/jci/opera/opera_home" \
         "$FAKE7/jci/sm" \
         "$FAKE7/jci/vim"

cat > "$FAKE7/jci/gui/apps/system/js/systemApp.js" <<'EOF'
systemApp.prototype.buildTemplates = function () {
    return {
        "Disclaimer" : {
            "template" : "NoCtrlTmplt",
            "displayedFunction" : this._displayedDisclaimer.bind(this),
        },
    };
};

systemApp.prototype._displayedDisclaimer = function () {
    return true;
};
EOF

cat > "$FAKE7/jci/gui/common/controls/List2/js/List2Ctrl.js" <<'EOF'
var List2Ctrl = function () {
    this.autoscrollTier1Timeout :                1500,
    this.autoscrollTier2Timeout :                5000,
    this.autoscrollTier1Interval :               500,
    this.autoscrollTier2Interval :               1000,
};
EOF

cat > "$FAKE7/jci/gui/resources/js/backupparking/backupparkingAppDict_NA.js" <<'EOF'
var dict = {
    "BUC-SafetyText" : "Always check your surroundings.",
    "BUC-Other" : "keep me"
};
EOF

printf '.NowPlaying4CtrlArtworkImageDiv {\n  top: 10px;\n}\n' \
  > "$FAKE7/jci/gui/common/controls/NowPlaying4/css/NowPlaying4Ctrl.css"
printf 'var NowPlaying4Ctrl = function () {};\n' \
  > "$FAKE7/jci/gui/common/controls/NowPlaying4/js/NowPlaying4Ctrl.js"
printf '.Ump3CtrlButtonIcon {\n  background-size: 32px 32px;\n}\n' \
  > "$FAKE7/jci/gui/common/controls/Ump3/css/Ump3Ctrl.css"

cat > "$FAKE7/jci/opera/opera_home/opera.ini" <<'EOF'
Console Error Log Enabled=0

[Disk Cache]
Enabled=0
Size=2000
Multimedia Stream Size=4096
EOF

cat > "$FAKE7/jci/vim/JCI_KEY_CONFIG.xml" <<'EOF'
<key_config>
  <sw1 codeSW1Button6="JCI_KEY_MUTE" />
</key_config>
EOF

cat > "$FAKE7/jci/gui/apps/system/controls/MainMenu/js/MainMenuCtrl.js" <<'EOF'
MainMenuCtrl.prototype._offsetFocus = function (direction) {
    var index = this._getFocus();
    index += direction;

    if (index < 0)
    {
        index = 0;
    }
    if (index > 4)
    {
        index = 4;
    }
    this._focusedIndex = index;
};
EOF

cat > "$FAKE7/jci/gui/common/js/Common.js" <<'EOF'
var Common = function () {
};

Common.prototype._init = function () {
    framework.addEventListener("common", {
        "Global.AtSpeed" : this._AtSpeedMsgHandler.bind(this),
        "Global.Other" : this._otherHandler.bind(this),
    });
};

Common.prototype.beep = function(pressType, eventCause)
{
    framework.sendEventToMmui("common", "Beep");
};
EOF

for app in usbaudio btaudio; do
  cat > "$FAKE7/jci/gui/apps/$app/js/${app}App.js" <<'EOF'
var notification = {
    text1 : msg.params.payload.album,
    text2 : msg.params.payload.title,
};
EOF
done

# Shaped like stock usbaudioApp.js on 74.00.324: the "Powered by Gracenote"
# detail line is set from three call sites inside the USB audio app.
cat >> "$FAKE7/jci/gui/apps/usbaudio/js/usbaudioApp.js" <<'EOF'
this._currentContextTemplate.nowPlaying4Ctrl.setDetailLine3({detailTextId: "Gracenote"});
this._currentContextTemplate.nowPlaying4Ctrl.setDetailLine3({detailTextId: "Gracenote"});
this._currentContextTemplate.nowPlaying4Ctrl.setDetailLine3({detailTextId: "Gracenote"});
EOF

cat > "$FAKE7/jci/gui/apps/carplay/js/carplayApp.js" <<'EOF'
carplayApp.prototype._SendCPSessionStateMsgHandler = function (msg) {
    this._cachedCPSessionState = msg.params;
};
EOF

# Shaped like the stock Service Manager config: one <service> block per unit,
# attributes on the opening line. jcixm is deliberately absent to exercise the
# regional-difference path.
cat > "$FAKE7/jci/sm/sm.conf" <<'EOF'
<service_manager>
  <service name="jciSXMS" autorun="yes" retry_count="0">
    <path>/jci/svc/jciSXMS.so</path>
  </service>
  <service name="jciXMMGR" autorun="yes" retry_count="0">
    <path>/jci/svc/jciXMMGR.so</path>
  </service>
  <service name="jciXMDATA" autorun="yes" retry_count="0">
    <path>/jci/svc/jciXMDATA.so</path>
  </service>
  <service name="jcixmad" autorun="yes" retry_count="0">
    <path>/jci/svc/jcixmad.so</path>
  </service>
  <service name="blm_ira_pandora" autorun="yes" retry_count="0">
    <path>/jci/svc/pandora.so</path>
  </service>
  <service name="irs_server" autorun="yes" retry_count="0">
    <path>/jci/svc/irs_server.so</path>
  </service>
  <service name="blm_ira_stitcher" autorun="yes" retry_count="0">
    <path>/jci/svc/stitcher.so</path>
  </service>
  <service name="irsstitcher_server" autorun="yes" retry_count="0">
    <path>/jci/svc/irsstitcher.so</path>
  </service>
  <service name="blm_ira_aha" autorun="yes" retry_count="0">
    <path>/jci/svc/aha.so</path>
  </service>
  <service name="jcidvd" autorun="yes" retry_count="0">
    <path>/jci/svc/dvd.so</path>
  </service>
  <stage name="stage_gap2">
    <wait value="blm_ira_aha"/>
  </stage>
  <stage name="stage_vr">
    <wait value="blm_ira_aha"/>
  </stage>
  <stage name="stage_wifi">
    <wait value="blm_ira_aha"/>
  </stage>
</service_manager>
EOF

run7() {
  sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE7" "$@"
}

PLAN="30-no-disclaimer 31-no-reverse-warning 32-shorter-delay 33-no-gracenote-text 34-bigger-album-art 35-usb-audio-mod 36-opera-cache-increase 37-mute-pause 40-menu-loop 41-list-loop 42-no-beeps 43-touch-while-driving 44-track-notification 45-carplay-autoforeground 46-disable-siriusxm 47-disable-pandora 48-disable-stitcher 49-disable-internet-radio-servers 50-disable-aha"
run7 --apply --experimental --tweaks "$PLAN" >/dev/null 2>"$TMP/warn7"
grep -qF 'MISSING jcixm' "$TMP/warn7" || fail "disable-siriusxm: absent service not reported"

SYS="$FAKE7/jci/gui/apps/system/js/systemApp.js"
grep -qF 'this._noMoreDisclaimer.bind(this)' "$SYS" || fail "no-disclaimer: binding not replaced"
grep -qF 'systemApp.prototype._noMoreDisclaimer = function' "$SYS" || fail "no-disclaimer: handler not inserted"
[ "$(grep -cF 'opencmu:no-disclaimer' "$SYS")" = "1" ] || fail "no-disclaimer: marker count wrong"
grep -qF 'framework.sendEventToMmui("system", "NotifyDisclaimerEnd");' "$SYS" || fail "no-disclaimer: body missing"

grep -qF '"BUC-SafetyText" : " "' "$FAKE7/jci/gui/resources/js/backupparking/backupparkingAppDict_NA.js" ||
  fail "no-reverse-warning: value not blanked"
grep -qF '"BUC-Other" : "keep me"' "$FAKE7/jci/gui/resources/js/backupparking/backupparkingAppDict_NA.js" ||
  fail "no-reverse-warning: unrelated entry changed"

grep -qF 'autoscrollTier1Timeout :                150,' "$FAKE7/jci/gui/common/controls/List2/js/List2Ctrl.js" ||
  fail "shorter-delay: tier1 timeout not shortened"
grep -qF 'autoscrollTier2Interval :               300,' "$FAKE7/jci/gui/common/controls/List2/js/List2Ctrl.js" ||
  fail "shorter-delay: tier2 interval not shortened"

grep -qF 'setDetailLine3({detailTextId: ""});' "$FAKE7/jci/gui/apps/usbaudio/js/usbaudioApp.js" ||
  fail "no-gracenote: detail line not cleared"
[ "$(grep -cF 'setDetailLine3({detailTextId: ""});' "$FAKE7/jci/gui/apps/usbaudio/js/usbaudioApp.js")" = "3" ] ||
  fail "no-gracenote: not all three call sites were cleared"
[ "$(grep -cF 'detailTextId: "Gracenote"' "$FAKE7/jci/gui/apps/usbaudio/js/usbaudioApp.js")" = "0" ] ||
  fail "no-gracenote: a Gracenote call site survived"

[ "$(grep -cF 'opencmu:bigger-album-art' "$FAKE7/jci/gui/common/controls/NowPlaying4/css/NowPlaying4Ctrl.css")" = "1" ] ||
  fail "bigger-album-art: marker count wrong"
[ "$(grep -cF 'opencmu:usb-audio-mod' "$FAKE7/jci/gui/common/controls/Ump3/css/Ump3Ctrl.css")" = "1" ] ||
  fail "usb-audio-mod: marker count wrong"

grep -qF 'Enabled=1' "$FAKE7/jci/opera/opera_home/opera.ini" ||
  fail "opera-cache: disk cache not enabled"
grep -qF 'Size=8000' "$FAKE7/jci/opera/opera_home/opera.ini" ||
  fail "opera-cache: disk cache size not raised"
[ "$(grep -cF 'Enabled=0' "$FAKE7/jci/opera/opera_home/opera.ini")" = "1" ] ||
  fail "opera-cache: the wrong Enabled= line was flipped"

grep -qF 'codeSW1Button6="JCI_KEY_PLAYPAUSE"' "$FAKE7/jci/vim/JCI_KEY_CONFIG.xml" ||
  fail "mute-pause: binding not remapped"

MENU="$FAKE7/jci/gui/apps/system/controls/MainMenu/js/MainMenuCtrl.js"
grep -qF 'index = this._coins.length - 1; // opencmu:menu-loop' "$MENU" ||
  fail "menu-loop: left edge not wrapped"
grep -qF 'if (index > this._coins.length - 1) // opencmu:menu-loop' "$MENU" ||
  fail "menu-loop: right edge not wrapped"

COMMON="$FAKE7/jci/gui/common/js/Common.js"
[ "$(grep -cF 'opencmu:list-loop' "$FAKE7/jci/gui/common/controls/List2/js/List2Ctrl.js")" = "1" ] ||
  fail "list-loop: block not appended once"
grep -qF 'Common.prototype.beep_stock = function(pressType, eventCause)' "$COMMON" ||
  fail "no-beeps: stock implementation not renamed"
[ "$(grep -cF 'opencmu:no-beeps' "$COMMON")" = "1" ] || fail "no-beeps: stub not inserted once"
[ "$(grep -cF '"Global.AtSpeed" : this._AtSpeedMsgHandler.bind(this),' "$COMMON")" = "0" ] ||
  fail "touch-while-driving: speed handler still registered"
grep -qF '// opencmu:touch-while-driving' "$COMMON" ||
  fail "touch-while-driving: marker missing"

grep -qF 'text2 : ((msg.params.payload.artist && msg.params.payload.title)' \
  "$FAKE7/jci/gui/apps/usbaudio/js/usbaudioApp.js" ||
  fail "track-notification: usbaudio payload not rewritten"
grep -qF 'text2 : msg.params.payload.title,' "$FAKE7/jci/gui/apps/btaudio/js/btaudioApp.js" ||
  fail "track-notification: btaudio must stay stock"

[ "$(grep -cF 'opencmu:carplay-autoforeground' "$FAKE7/jci/gui/apps/carplay/js/carplayApp.js")" = "1" ] ||
  fail "carplay-autoforeground: block not appended once"

SM="$FAKE7/jci/sm/sm.conf"
[ "$(grep -cF 'autorun="no"' "$SM")" = "9" ] || fail "disable-*: wrong number of services switched off"
grep -qF '<service name="jcidvd" autorun="yes"' "$SM" || fail "disable-*: untouched service was modified"
[ "$(grep -cF 'value="stage_ir"' "$SM")" = "3" ] || fail "disable-aha: stage waits not rewired"
[ "$(grep -cF 'value="blm_ira_aha"' "$SM")" = "0" ] || fail "disable-aha: stage still waits on Aha"
pass "firmware text patches apply"

# 14b. Rollback restores every patched file byte for byte.
run7 --apply --rollback >/dev/null
grep -qF 'this._displayedDisclaimer.bind(this)' "$SYS" || fail "rollback: disclaimer binding not restored"
grep -qF 'autoscrollTier1Timeout :                1500,' "$FAKE7/jci/gui/common/controls/List2/js/List2Ctrl.js" ||
  fail "rollback: list delay not restored"
grep -qF '"BUC-SafetyText" : "Always check your surroundings."' "$FAKE7/jci/gui/resources/js/backupparking/backupparkingAppDict_NA.js" ||
  fail "rollback: reverse warning not restored"
[ "$(grep -cF 'setDetailLine3({detailTextId: "Gracenote"});' "$FAKE7/jci/gui/apps/usbaudio/js/usbaudioApp.js")" = "3" ] ||
  fail "rollback: gracenote call sites not restored"
grep -qF 'Enabled=0' "$FAKE7/jci/opera/opera_home/opera.ini" ||
  fail "rollback: opera disk cache not restored"
grep -qF 'Size=2000' "$FAKE7/jci/opera/opera_home/opera.ini" ||
  fail "rollback: opera disk cache size not restored"
grep -qF 'codeSW1Button6="JCI_KEY_MUTE"' "$FAKE7/jci/vim/JCI_KEY_CONFIG.xml" ||
  fail "rollback: key binding not restored"
[ "$(grep -cF 'opencmu:bigger-album-art' "$FAKE7/jci/gui/common/controls/NowPlaying4/css/NowPlaying4Ctrl.css" || true)" = "0" ] ||
  fail "rollback: appended block left behind"
[ "$(grep -cF 'opencmu:list-loop' "$FAKE7/jci/gui/common/controls/List2/js/List2Ctrl.js" || true)" = "0" ] ||
  fail "rollback: list-loop block left behind"
[ "$(grep -cF 'opencmu:carplay-autoforeground' "$FAKE7/jci/gui/apps/carplay/js/carplayApp.js" || true)" = "0" ] ||
  fail "rollback: carplay block left behind"
grep -qF '"Global.AtSpeed" : this._AtSpeedMsgHandler.bind(this),' "$COMMON" ||
  fail "rollback: speed handler not restored"
grep -qF 'Common.prototype.beep = function(pressType, eventCause)' "$COMMON" ||
  fail "rollback: beep not restored"
[ "$(grep -cF 'autorun="no"' "$SM" || true)" = "0" ] || fail "rollback: services not restored"
[ "$(grep -cF 'value="blm_ira_aha"' "$SM" || true)" = "3" ] || fail "rollback: stage waits not restored"
pass "firmware text patches roll back"

# 14b2. A single-tweak rollback must also restore its file byte for byte.
# A batch rollback cannot prove this: when two tweaks patch the same file, the
# other tweak's rollback can mask a tweak that rolls back the wrong file.
run7 --apply --experimental --tweaks 33-no-gracenote-text >/dev/null
grep -qF 'setDetailLine3({detailTextId: ""});' "$FAKE7/jci/gui/apps/usbaudio/js/usbaudioApp.js" ||
  fail "single-tweak rollback setup: gracenote not patched"
run7 --apply --rollback >/dev/null
[ "$(grep -cF 'setDetailLine3({detailTextId: "Gracenote"});' "$FAKE7/jci/gui/apps/usbaudio/js/usbaudioApp.js")" = "3" ] ||
  fail "single-tweak rollback: gracenote call sites not restored"
run7 --apply --experimental --tweaks 44-track-notification >/dev/null
run7 --apply --rollback >/dev/null
grep -qF 'text2 : msg.params.payload.title,' "$FAKE7/jci/gui/apps/usbaudio/js/usbaudioApp.js" ||
  fail "single-tweak rollback: usbaudio payload not restored"
pass "single-tweak rollbacks restore their own file"

# 14c. Re-applying must not duplicate the appended blocks.
run7 --apply --experimental --tweaks "34-bigger-album-art 35-usb-audio-mod 41-list-loop 42-no-beeps 45-carplay-autoforeground" >/dev/null
rm -f "$FAKE7/data/opencmu/state/receipt.env" "$FAKE7/data/opencmu/state/receipt.json"
: > "$FAKE7/data/opencmu/state/installed.list"
run7 --apply --experimental --tweaks "34-bigger-album-art 35-usb-audio-mod 41-list-loop 42-no-beeps 45-carplay-autoforeground" >/dev/null
[ "$(grep -cF 'opencmu:bigger-album-art' "$FAKE7/jci/gui/common/controls/NowPlaying4/css/NowPlaying4Ctrl.css")" = "1" ] ||
  fail "bigger-album-art duplicated on re-apply"
[ "$(grep -cF 'opencmu:list-loop' "$FAKE7/jci/gui/common/controls/List2/js/List2Ctrl.js")" = "1" ] ||
  fail "list-loop duplicated on re-apply"
[ "$(grep -cF 'opencmu:carplay-autoforeground' "$FAKE7/jci/gui/apps/carplay/js/carplayApp.js")" = "1" ] ||
  fail "carplay-autoforeground duplicated on re-apply"
[ "$(grep -cF 'opencmu:no-beeps' "$COMMON")" = "1" ] || fail "no-beeps duplicated on re-apply"
[ "$(grep -cF 'Common.prototype.beep_stock = function' "$COMMON")" = "1" ] ||
  fail "no-beeps renamed twice on re-apply"
[ "$(grep -cF 'opencmu:usb-audio-mod' "$FAKE7/jci/gui/common/controls/Ump3/css/Ump3Ctrl.css")" = "1" ] ||
  fail "usb-audio-mod duplicated on re-apply"
pass "text patches are idempotent"

# 14d. A missing anchor aborts before writing anything.
FAKE8="$TMP/root8"
make_root "$FAKE8"
mkdir -p "$FAKE8/jci/gui/apps/system/js"
printf 'systemApp.prototype.buildTemplates = function () { return {}; };\n' \
  > "$FAKE8/jci/gui/apps/system/js/systemApp.js"
BEFORE=$(hash "$FAKE8/jci/gui/apps/system/js/systemApp.js")
if sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE8" \
     --apply --experimental --tweaks 30-no-disclaimer >/dev/null 2>&1; then
  fail "missing anchor was accepted"
fi
[ "$(hash "$FAKE8/jci/gui/apps/system/js/systemApp.js")" = "$BEFORE" ] ||
  fail "missing anchor still modified the target"
pass "missing anchor aborts without writing"

# 14e. A service set this firmware does not have must not be half-applied.
FAKE9="$TMP/root9"
make_root "$FAKE9"
mkdir -p "$FAKE9/jci/sm"
cat > "$FAKE9/jci/sm/sm.conf" <<'EOF'
<service_manager>
  <service name="jcidvd" autorun="yes" retry_count="0">
    <path>/jci/svc/dvd.so</path>
  </service>
  <stage name="stage_vr">
    <wait value="blm_ira_aha"/>
  </stage>
  <stage name="stage_wifi">
    <wait value="blm_ira_aha"/>
  </stage>
</service_manager>
EOF
SM9="$FAKE9/jci/sm/sm.conf"
SM9BEFORE=$(hash "$SM9")

if sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE9" \
     --apply --experimental --tweaks 46-disable-siriusxm >/dev/null 2>&1; then
  fail "service set with no match was accepted"
fi
[ "$(hash "$SM9")" = "$SM9BEFORE" ] || fail "failed service patch still wrote sm.conf"

# The Aha tweak needs three stage waits; two must abort before the first write,
# leaving both the waits and the service alone.
if sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE9" \
     --apply --experimental --tweaks 50-disable-aha >/dev/null 2>&1; then
  fail "Aha tweak accepted an incomplete stage set"
fi
[ "$(hash "$SM9")" = "$SM9BEFORE" ] || fail "failed Aha patch still wrote sm.conf"
pass "service patches abort before writing"

# 14f. Boot and runtime tweaks: WebSockets, DLT, tranlogo, CPU affinity,
# and the config-driven off-board service.
FAKE10="$TMP/root10"
make_root "$FAKE10"
mkdir -p "$FAKE10/jci/gui/framework/js" "$FAKE10/jci/sm" "$FAKE10/etc" "$FAKE10/jci/scripts"

cat > "$FAKE10/jci/scripts/start_wifi.sh" <<'EOF'
#!/bin/sh
case $MODEVALUE in
start)
    # Load the WIFI modules
    insmod /lib/modules/wl12xx.ko
    ;;
stop)
    rmmod wl12xx
    ;;
esac
EOF

cat > "$FAKE10/jci/gui/framework/js/Websockets.js" <<'EOF'
function _isStack(item) {
    return false;
}

function _delStack(item) {
    return false;
}
EOF

cat > "$FAKE10/etc/dlt.conf" <<'EOF'
[General]
SendMessageTime = 500
SharedMemorySize = 4000000
EOF

cat > "$FAKE10/jci/sm/sm.conf" <<'EOF'
<service_manager>
  <service name="tranlogo" type="process" exit_allowed="yes" ready_flag="/var/run/tranlogo_ready_flag">
    <exec>/usr/bin/splashplayer</exec>
  </service>
  <service name="start_wifi" autorun="yes" retry_count="0">
    <path>/jci/scripts/jci-wifiap.sh</path>
  </service>
  <service name="NMS_svc" autorun="yes" affinity_mask="0x01" retry_count="0">
    <path>/jci/svc/nms.so</path>
  </service>
  <service name="blm_nms_svc" autorun="yes" affinity_mask="0x01" retry_count="0">
    <path>/jci/svc/nms_blm.so</path>
  </service>
  <service name="jciCARPLAY" autorun="yes" affinity_mask="0x01" retry_count="0">
    <path>/jci/svc/carplay.so</path>
  </service>
  <service name="carplayd" autorun="yes" retry_count="0">
    <path>/usr/bin/carplayd</path>
  </service>
  <service name="jciDAB" autorun="yes" retry_count="0">
    <path>/jci/svc/dab.so</path>
  </service>
</service_manager>
EOF

SM10="$FAKE10/jci/sm/sm.conf"
DUPES_BEFORE=$(grep -cF 'opencmu:' "$SM10" || true)

OPENCMU_OFFBOARD_SERVICE=jciDAB sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE10" \
  --apply --experimental \
  --tweaks "51-fix-websocket-msg-ordering 52-dlt-logging-reduction 53-skip-startup-animation 54-wifi-boot-off-busy-core 55-carplay-engine-off-busy-core 56-disable-offboard 74-earlier-wifi-init" >/dev/null

WS="$FAKE10/jci/gui/framework/js/Websockets.js"
grep -qF 'Websockets.prototype._isStack = function(' "$WS" || fail "websockets: _isStack not exposed"
grep -qF 'Websockets.prototype._delStack = function(' "$WS" || fail "websockets: _delStack not exposed"

DLT="$FAKE10/etc/dlt.conf"
grep -qF 'SendMessageTime = 0' "$DLT" || fail "dlt: send interval not reduced"
grep -qF 'SharedMemorySize = 1048576' "$DLT" || fail "dlt: shared memory not reduced"

grep -qF '<service name="tranlogo" type="process" exit_allowed="yes" ready_flag="/var/run/tranlogo_ready_flag" autorun="no">' "$SM10" ||
  fail "skip-startup-animation: tranlogo not disabled"
WF="$FAKE10/jci/scripts/start_wifi.sh"
grep -qF 'opencmu:earlier-wifi-init' "$WF" || fail "wifi-init: wait loop not inserted"
[ "$(grep -cF '/sys/class/net/wlan0' "$WF")" = "1" ] || fail "wifi-init: wait loop duplicated"
grep -qF 'name="start_wifi" autorun="yes" retry_count="0" affinity_mask="0x02"' "$SM10" ||
  fail "wifi-core: start_wifi affinity not set"
grep -qF 'name="NMS_svc" autorun="yes" affinity_mask="0x02" retry_count="0"' "$SM10" ||
  fail "wifi-core: NMS_svc affinity not set"
grep -qF 'name="blm_nms_svc" autorun="yes" affinity_mask="0x02" retry_count="0"' "$SM10" ||
  fail "wifi-core: blm_nms_svc affinity not set"
grep -qF 'name="jciCARPLAY" autorun="yes" affinity_mask="0x02"' "$SM10" ||
  fail "carplay-core: affinity not rewritten"
! grep -qF 'name="carplayd" autorun="yes" retry_count="0" affinity_mask' "$SM10" ||
  fail "carplay-core: carplayd should stay untouched"
grep -qF '<service name="jciDAB" autorun="no"' "$SM10" ||
  fail "disable-offboard: configured service not disabled"
[ "$(grep -cF 'opencmu:' "$SM10" || true)" = "$DUPES_BEFORE" ] || fail "boot tweaks wrote a marker into sm.conf"
pass "boot and runtime tweaks apply"


sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE10" --apply --rollback >/dev/null
grep -qF 'function _isStack(' "$WS" || fail "rollback: websockets not restored"
grep -qF 'SendMessageTime = 500' "$DLT" || fail "rollback: dlt not restored"
! grep -qF 'opencmu:earlier-wifi-init' "$WF" || fail "rollback: wifi wait loop left behind"
! grep -qF 'autorun="no"' "$SM10" || fail "rollback: sm.conf not restored"
! grep -qF 'affinity_mask="0x02"' "$SM10" || fail "rollback: affinity left behind"
pass "boot and runtime tweaks roll back"

# 14f-bis. Applying again over the patched tree must not duplicate or re-insert
# anything. The receipt is cleared to bypass the guard, not the tweak logic.
OPENCMU_OFFBOARD_SERVICE=jciDAB sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE10" \
  --apply --experimental \
  --tweaks "51-fix-websocket-msg-ordering 52-dlt-logging-reduction 53-skip-startup-animation 54-wifi-boot-off-busy-core 55-carplay-engine-off-busy-core 56-disable-offboard 74-earlier-wifi-init" >/dev/null
rm -f "$FAKE10/data/opencmu/state/receipt.env" "$FAKE10/data/opencmu/state/receipt.json"
: > "$FAKE10/data/opencmu/state/installed.list"
OPENCMU_OFFBOARD_SERVICE=jciDAB sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE10" \
  --apply --experimental \
  --tweaks "51-fix-websocket-msg-ordering 52-dlt-logging-reduction 53-skip-startup-animation 54-wifi-boot-off-busy-core 55-carplay-engine-off-busy-core 56-disable-offboard 74-earlier-wifi-init" >/dev/null
[ "$(grep -cF 'Websockets.prototype._isStack = function(' "$WS")" = "1" ] ||
  fail "websockets duplicated on re-apply"
[ "$(grep -cF 'SendMessageTime = 0' "$DLT")" = "1" ] || fail "dlt duplicated on re-apply"
[ "$(grep -cF 'affinity_mask="0x02"' "$SM10")" = "4" ] || fail "affinity duplicated on re-apply"
[ "$(grep -cF 'opencmu:earlier-wifi-init' "$WF")" = "1" ] || fail "wifi wait loop duplicated on re-apply"
[ "$(grep -cF 'autorun="no"' "$SM10")" = "2" ] || fail "autorun duplicated on re-apply"
pass "boot and runtime tweaks are idempotent"

# 14g. The off-board tweak refuses to guess a service name.
if sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE10" \
     --apply --experimental --tweaks 56-disable-offboard >/dev/null 2>&1; then
  fail "disable-offboard ran without a service name"
fi
pass "disable-offboard requires a target"

# 15a. Firewall, AA touch, and the startup hook.
FAKE11="$TMP/root11"
make_root "$FAKE11"
mkdir -p "$FAKE11/jci/scripts" "$FAKE11/jci/sm" "$FAKE11/etc" "$FAKE11/data_persist"

cat > "$FAKE11/jci/scripts/jci-fw.sh" <<'EOF'
#!/bin/sh
firewall_start() {
    log "installing firewall rules one by one"
}
firewall_start "$1"
EOF

cat > "$FAKE11/jci/scripts/stage_gap2.sh" <<'EOF'
#!/bin/sh
start_vehicle_services
EOF

cat > "$FAKE11/etc/aap_system_attributes.xml" <<'EOF'
<aap_system>
    <input_devices>
        <device name="touch"/>
    </input_devices>
    <key_codes>
        <key code="1"/>
    </key_codes>
</aap_system>
EOF
cp "$FAKE11/etc/aap_system_attributes.xml" "$FAKE11/etc/aap_system_attributes_UCP.xml"

cat > "$FAKE11/jci/sm/sm.conf" <<'EOF'
<service_manager>
  <service name="jciAAPA" autorun="yes" reset_board="yes" retry_count="0">
    <path>/usr/bin/aap_service</path>
  </service>
</service_manager>
EOF

RULES11="$TMP/wcp.rules"
cat > "$RULES11" <<'EOF'
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i wlan0 -p udp --dport 53 -j ACCEPT
COMMIT
EOF

SHIM11="$TMP/libpatch-blmjciaapa.so"
printf 'not a real shim\n' > "$SHIM11"
SHIM11_SUM=$(hash "$SHIM11")

run11() {
  OPENCMU_WCP_RULES="$RULES11" \
  OPENCMU_FW_ANCHOR='firewall_start() {' \
  OPENCMU_AATOUCH_SHIM="$SHIM11" \
  OPENCMU_AATOUCH_SHA256="$SHIM11_SUM" \
  sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE11" "$@"
}

FW11="$FAKE11/jci/scripts/jci-fw.sh"
XML11="$FAKE11/etc/aap_system_attributes.xml"
UCP11="$FAKE11/etc/aap_system_attributes_UCP.xml"
SM11="$FAKE11/jci/sm/sm.conf"
ST11="$FAKE11/jci/scripts/stage_gap2.sh"

run11 --apply --experimental \
  --tweaks "57-firewall-iptables-restore 58-install-aatouch 59-enable-aa-touch 60-startup-hook" >/dev/null

grep -qF 'opencmu:firewall-iptables-restore' "$FW11" || fail "firewall: fast path not inserted"
cmp -s "$RULES11" "$FAKE11/jci/scripts/jci-fw-wcp.rules" || fail "firewall: ruleset not installed"
[ -x "$FAKE11/data_persist/oem-aa-mod/libpatch-blmjciaapa.so" ] || fail "aatouch: shim not installed"
grep -qF 'touch = true' "$FAKE11/data_persist/oem-aa-mod/libpatch.conf" || fail "aatouch: config not written"
grep -qF '<use_internally>true</use_internally>' "$XML11" || fail "aa-touch: primary block missing"
grep -qF '<use_internally>false</use_internally>' "$UCP11" || fail "aa-touch: secondary block missing"
grep -qF 'reset_board="no"' "$SM11" || fail "aa-touch: reset_board not set"
grep -qF 'env_name="LD_PRELOAD"' "$SM11" || fail "aa-touch: preload not added"
grep -qF 'opencmu:boot-hook' "$ST11" || fail "startup-hook: block not appended"
[ -f "$FAKE11/data/opencmu/boot.d/README.txt" ] || fail "startup-hook: boot.d not created"
pass "firewall, AA touch, and startup hook apply"

sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE11" --apply --rollback >/dev/null
! grep -qF 'opencmu:firewall-iptables-restore' "$FW11" || fail "rollback: jci-fw.sh not restored"
[ ! -f "$FAKE11/jci/scripts/jci-fw-wcp.rules" ] || fail "rollback: ruleset left behind"
[ ! -f "$FAKE11/data_persist/oem-aa-mod/libpatch-blmjciaapa.so" ] || fail "rollback: shim left behind"
! grep -qF '<touch_screen>' "$XML11" || fail "rollback: XML not restored"
! grep -qF 'reset_board="no"' "$SM11" || fail "rollback: sm.conf not restored"
! grep -qF 'opencmu:boot-hook' "$ST11" || fail "rollback: stage script not restored"
pass "firewall, AA touch, and startup hook roll back"

# From stock again: apply once, then apply again over the patched tree. The
# receipt is cleared between runs to bypass the guard, not the tweak logic.
run11 --apply --experimental \
  --tweaks "57-firewall-iptables-restore 58-install-aatouch 59-enable-aa-touch 60-startup-hook" >/dev/null
rm -f "$FAKE11/data/opencmu/state/receipt.env" "$FAKE11/data/opencmu/state/receipt.json"
: > "$FAKE11/data/opencmu/state/installed.list"
run11 --apply --experimental \
  --tweaks "57-firewall-iptables-restore 58-install-aatouch 59-enable-aa-touch 60-startup-hook" >/dev/null
[ "$(grep -cF '<touch_screen>' "$XML11")" = "1" ] || fail "aa-touch: duplicate touch block"
[ "$(grep -cF 'env_name="LD_PRELOAD"' "$SM11")" = "1" ] || fail "aa-touch: duplicate preload"
[ "$(grep -cF 'opencmu:boot-hook' "$ST11")" = "1" ] || fail "startup-hook: duplicate block"
[ "$(grep -cF 'opencmu:firewall-iptables-restore' "$FW11")" = "1" ] || fail "firewall: duplicate fast path"
pass "firewall, AA touch, and startup hook are idempotent"



# 15b. The three new tweaks refuse to guess their inputs.
if OPENCMU_WCP_RULES="$RULES11" sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE11" \
     --apply --experimental --tweaks 57-firewall-iptables-restore >/dev/null 2>&1; then
  fail "firewall: ran without an anchor"
fi
if OPENCMU_AATOUCH_SHIM="$SHIM11" OPENCMU_AATOUCH_SHA256=deadbeef \
   sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE11" \
     --apply --experimental --tweaks 58-install-aatouch >/dev/null 2>&1; then
  fail "aatouch: accepted a wrong digest"
fi
if sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE11" \
     --apply --experimental --tweaks 59-enable-aa-touch >/dev/null 2>&1; then
  fail "aa-touch: enabled without the shim"
fi
pass "new tweaks refuse to guess their inputs"

# 16. keep-cluster-compass: refuses without the boot hook, then installs a
# runtime into boot.d and removes it on rollback.
FAKE12="$TMP/root12"
make_root "$FAKE12"
mkdir -p "$FAKE12/jci/scripts"

cat > "$FAKE12/jci/scripts/stage_gap2.sh" <<'EOF'
#!/bin/sh
start_vehicle_services
EOF

run12() {
  sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE12" "$@"
}

if run12 --apply --experimental --tweaks 61-keep-cluster-compass >/dev/null 2>&1; then
  fail "compass: ran without the boot hook"
fi
[ ! -e "$FAKE12/data/opencmu/boot.d/61-cluster-compass.sh" ] ||
  fail "compass: wrote the runtime on a failed run"
rm -f "$FAKE12/data/opencmu/state/receipt.env" "$FAKE12/data/opencmu/state/receipt.json"
: > "$FAKE12/data/opencmu/state/installed.list"

run12 --apply --experimental \
  --tweaks "60-startup-hook 61-keep-cluster-compass" >/dev/null

CC12="$FAKE12/data/opencmu/boot.d/61-cluster-compass.sh"
[ -x "$CC12" ] || fail "compass: runtime not installed or not executable"
sh -n "$CC12" || fail "compass: runtime has a syntax error"
grep -qF 'NoSpeedRestrict_TouchDisplay' "$CC12" || fail "compass: member missing"
grep -qF 'unix:path=/tmp/dbus_service_socket' "$CC12" || fail "compass: socket missing"
out=$(OPENCMU_COMPASS_LOCK="$TMP/cc.lock" sh "$CC12" --status || true)
[ "$out" = "not running" ] || fail "compass: status should report not running"
pass "keep-cluster-compass installs a boot runtime"

run12 --apply --rollback >/dev/null
[ ! -f "$CC12" ] || fail "compass: rollback left the runtime behind"
pass "keep-cluster-compass rolls back"

# 17. The ScreenTune-parity batch: service switches, artwork, touchscreen,
# Wi-Fi init, SSH and Wi-Fi client.
FAKE13="$TMP/root13"
make_root "$FAKE13"
mkdir -p "$FAKE13/jci/scripts" "$FAKE13/jci/sm" \
         "$FAKE13/jci/gui/common/controls/NowPlaying4/js" \
         "$FAKE13/jci/gui/apps/system/js" \
         "$FAKE13/etc/ssh"

cat > "$FAKE13/jci/scripts/start_wifi.sh" <<'EOF'
#!/bin/sh
case $MODEVALUE in
start)
    # Load the WIFI modules
    insmod /lib/modules/wl12xx.ko
    ;;
stop)
    rmmod wl12xx
    ;;
esac
EOF

cat > "$FAKE13/jci/scripts/stage_gap2.sh" <<'EOF'
#!/bin/sh
start_vehicle_services
EOF

cat > "$FAKE13/jci/gui/common/controls/NowPlaying4/js/NowPlaying4Ctrl.js" <<'EOF'
NowPlaying4Ctrl.prototype.setArtworkImagePath = function(imagePath)
{
    log.debug("setArtworkImagePath() called: " + imagePath);

    // Album Image
    if (imagePath)
    {
        this.properties.artworkImagePath = imagePath;
        this._artworkImage.src = this.properties.artworkImagePath;
    }
    else
    {
        if (this.properties.ctrlStyle === "Style6")
        {
            this._artworkImageFrame.className = "NowPlaying4CtrlHidden";
        }
        else
        {
            this.properties.artworkImagePath = "";
        	this._artworkImage.src = this.properties.noArtworkImagePath;
        }
    }
};
EOF

cat > "$FAKE13/jci/gui/apps/system/js/systemApp.js" <<'EOF'
systemApp.prototype._buildEntertainmentDataList = function () {
    return { items: [], itemCount: 0 };
};

systemApp.prototype._StatusMenuBTAudioMsgHandler = function (msg) {
    this._lastBtPayload = msg && msg.params && msg.params.payload;
};
EOF

cat > "$FAKE13/etc/ssh/sshd_config" <<'EOF'
# OpenSSH 5.9 stock
Port 36000
PermitRootLogin yes
PasswordAuthentication yes
EOF

cat > "$FAKE13/jci/sm/sm.conf" <<'EOF'
<service_manager>
  <service name="blm_ira_pandora" autorun="yes" retry_count="0">
    <path>/jci/svc/pandora.so</path>
  </service>
  <service name="blm_ira_stitcher" autorun="yes" retry_count="0">
    <path>/jci/svc/stitcher.so</path>
  </service>
  <service name="irs_server" autorun="yes" retry_count="0">
    <path>/jci/svc/irs_server.so</path>
  </service>
  <service name="irsstitcher_server" autorun="yes" retry_count="0">
    <path>/jci/svc/irsstitcher.so</path>
  </service>
  <service name="start_wifi" autorun="yes" retry_count="0">
    <path>/jci/scripts/jci-wifiap.sh</path>
  </service>
  <service name="NMS_svc" autorun="yes" affinity_mask="0x01" retry_count="0">
    <path>/jci/svc/nms.so</path>
  </service>
  <service name="blm_nms_svc" autorun="yes" affinity_mask="0x01" retry_count="0">
    <path>/jci/svc/nms_blm.so</path>
  </service>
  <service name="jciCD" autorun="yes" retry_count="0"><path>/jci/svc/cd.so</path></service>
  <service name="jcidvd" autorun="yes" retry_count="0"><path>/jci/svc/dvd.so</path></service>
  <service name="jcitv" autorun="yes" retry_count="0"><path>/jci/svc/tv.so</path></service>
  <service name="jciDAB" autorun="yes" retry_count="0"><path>/jci/svc/dab.so</path></service>
  <service name="jciVUI" autorun="yes" retry_count="0"><path>/jci/svc/vui.so</path></service>
  <service name="jcitraffic" autorun="yes" retry_count="0"><path>/jci/svc/traffic.so</path></service>
  <service name="jciTestDiag" autorun="yes" retry_count="0"><path>/jci/svc/diag.so</path></service>
  <service name="kapture" autorun="yes" retry_count="0"><path>/usr/bin/kapture</path></service>
  <service name="jciEem" autorun="yes" retry_count="0"><path>/jci/svc/eem.so</path></service>
  <service name="jciVwm" autorun="yes" retry_count="0"><path>/jci/svc/vwm.so</path></service>
  <service name="jciDriverid" autorun="yes" retry_count="0"><path>/jci/svc/driverid.so</path></service>
  <service name="jciblmVdt" autorun="yes" retry_count="0"><path>/jci/svc/vdt.so</path></service>
  <service name="jciIdm" autorun="yes" retry_count="0"><path>/jci/svc/idm.so</path></service>
  <service name="jciVdtcon" autorun="yes" retry_count="0"><path>/jci/svc/vdtcon.so</path></service>
  <service name="jcinavi" autorun="yes" retry_count="0"><path>/jci/svc/navi.so</path></service>
  <service name="JVMM" autorun="yes" retry_count="0"><path>/jci/svc/jvmm.so</path></service>
</service_manager>
EOF

KEY13="$TMP/id_rsa.pub"
printf 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7 bench@opencmu\n' > "$KEY13"

run13() {
  OPENCMU_SSH_PUBKEY="$KEY13" OPENCMU_SSH_START=0 \
  OPENCMU_WIFI_SSID='OpenCMU Bench' OPENCMU_WIFI_PSK='correct horse battery staple' \
  OPENCMU_AUDIO_ORDER='BTAudio,USB_A' \
  sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE13" "$@"
}

PLAN13="38-order-audio-sources 47-disable-pandora 48-disable-stitcher 54-wifi-boot-off-busy-core 60-startup-hook 62-disable-touchscreen 63-no-blank-art 64-disable-jcicd 65-disable-dvd 66-disable-tv 67-disable-dab 68-disable-voice 69-disable-traffic 70-disable-diagnostics 71-disable-telematics 72-disable-nav 73-disable-jvmm 74-earlier-wifi-init 75-enable-ssh 76-enable-wifi-client 77-boot-profiler 78-select-bt-audio-first"
run13 --apply --experimental --tweaks "$PLAN13" >/dev/null

SM13="$FAKE13/jci/sm/sm.conf"
NP13="$FAKE13/jci/gui/common/controls/NowPlaying4/js/NowPlaying4Ctrl.js"
SY13="$FAKE13/jci/gui/apps/system/js/systemApp.js"
WF13="$FAKE13/jci/scripts/start_wifi.sh"
SSH13="$FAKE13/etc/ssh/sshd_config"
KEYS13="$FAKE13/data/opencmu/ssh/authorized_keys"
WCONF13="$FAKE13/data/opencmu/config/wifi-client.conf"
WPA13="$FAKE13/data/opencmu/wifi/wpa_supplicant.conf"
TOUCH13="$FAKE13/data/opencmu/boot.d/62-disable-touchscreen.sh"
WIFI13="$FAKE13/data/opencmu/boot.d/76-wifi-client.sh"
PROF13="$FAKE13/data/opencmu/boot.d/77-boot-profiler.sh"

[ "$(grep -cF 'autorun="no"' "$SM13")" = "18" ] || fail "disable batch: wrong number of services switched off"
grep -qF 'name="irs_server" autorun="yes"' "$SM13" || fail "47/48: shared IR server was disabled"
grep -qF 'name="irsstitcher_server" autorun="yes"' "$SM13" || fail "47/48: shared IR stitcher server was disabled"
grep -qF 'name="blm_ira_pandora" autorun="no"' "$SM13" || fail "disable-pandora: service not disabled"
grep -qF 'name="blm_ira_stitcher" autorun="no"' "$SM13" || fail "disable-stitcher: service not disabled"
for svc in jciCD jcidvd jcitv jciDAB jciVUI jcitraffic jciTestDiag kapture jciEem jciVwm jciDriverid jciblmVdt jciIdm jciVdtcon jcinavi JVMM; do
  grep -qF "name=\"$svc\" autorun=\"no\"" "$SM13" || fail "disable batch: $svc not disabled"
done

[ "$(grep -cF 'affinity_mask="0x02"' "$SM13")" = "3" ] || fail "wifi-core: wrong affinity count"
grep -qF 'name="start_wifi" autorun="yes" retry_count="0" affinity_mask="0x02"' "$SM13" ||
  fail "wifi-core: start_wifi not pinned"
grep -qF 'name="NMS_svc" autorun="yes" affinity_mask="0x02" retry_count="0"' "$SM13" ||
  fail "wifi-core: NMS_svc not pinned"
grep -qF 'name="blm_nms_svc" autorun="yes" affinity_mask="0x02" retry_count="0"' "$SM13" ||
  fail "wifi-core: blm_nms_svc not pinned"

[ "$(grep -cF 'opencmu:earlier-wifi-init' "$WF13")" = "1" ] || fail "earlier-wifi-init: block count wrong"
grep -qF 'opencmu:no-blank-art' "$NP13" || fail "no-blank-art: marker missing"
grep -A1 'this.properties.artworkImagePath = imagePath;' "$NP13" | grep -qF 'NowPlaying4CtrlArtworkImageDiv' ||
  fail "no-blank-art: frame class not inserted after the assignment"

[ "$(grep -cF 'opencmu:order-audio-sources' "$SY13")" = "1" ] ||
  fail "order-audio-sources: marker count wrong"
grep -qF 'preferredAudioSourceIds = "BTAudio,USB_A"' "$SY13" ||
  fail "order-audio-sources: requested order not installed"
grep -qF 'opencmuAudioOrderWrapped' "$SY13" || fail "order-audio-sources: guard missing"

[ "$(grep -cF 'opencmu:select-bt-audio-first' "$SY13")" = "1" ] ||
  fail "select-bt-audio-first: marker count wrong"
grep -qF 'systemApp.prototype._StatusMenuBTAudioMsgHandler = wrapped;' "$SY13" ||
  fail "select-bt-audio-first: handler not wrapped"
grep -qF 'opencmuBtAudioFirstWrapped' "$SY13" ||
  fail "select-bt-audio-first: guard missing"
if command -v node >/dev/null 2>&1; then
  node --check "$SY13" || fail "systemApp.js appended JS does not parse"

  # Behavior: an Available message with a device name must result in exactly
  # one SelectBTAudio, later Available messages must not repeat it, and an
  # Available message without a device name must not select at all.
  TMP78="$TMP/bt78"
  mkdir -p "$TMP78"
  cat > "$TMP78/harness.js" <<'EOF'
function systemApp() { this.uiaId = "system"; }
systemApp.prototype._buildEntertainmentDataList = function () {
    return { items: [], itemCount: 0 };
};
systemApp.prototype._StatusMenuBTAudioMsgHandler = function (msg) {
    this._lastBtPayload = msg && msg.params && msg.params.payload;
};
var events = [];
var framework = { sendEventToMmui: function (uiaId, event) { events.push(uiaId + ":" + event); } };
var log = { debug: function () {} };
EOF
  cat "$SY13" >> "$TMP78/harness.js"
  cat >> "$TMP78/harness.js" <<'EOF'
var app = new systemApp();
var available = { params: { payload: { appStatus: "Available", deviceName: "Phone" } } };
app._StatusMenuBTAudioMsgHandler(available);
app._StatusMenuBTAudioMsgHandler(available);
app._StatusMenuBTAudioMsgHandler({ params: { payload: { appStatus: "Available", deviceName: "Phone" } } });
app._StatusMenuBTAudioMsgHandler({ params: { payload: { appStatus: "Available" } } });
app._StatusMenuBTAudioMsgHandler({ params: { payload: { appStatus: "Unavailable", deviceName: "Phone" } } });
var selected = events.filter(function (e) { return e === "system:SelectBTAudio"; });
if (selected.length !== 1) {
    console.error("SelectBTAudio fired " + selected.length + " times, expected 1");
    process.exit(1);
}
if (events.length !== 1) {
    console.error("extra events sent: " + events.join(","));
    process.exit(1);
}
if (app._lastBtPayload.deviceName !== "Phone") {
    console.error("stock handler did not run");
    process.exit(1);
}
EOF
  node "$TMP78/harness.js" || fail "select-bt-audio-first: behavior test failed"
  rm -rf "$TMP78"
fi

if [ ! -x "$TOUCH13" ] || ! sh -n "$TOUCH13"; then
  fail "disable-touchscreen: runtime missing or invalid"
fi
grep -qF 'com.jci.lvds.SpeedRestriction' "$TOUCH13" || fail "disable-touchscreen: member missing"
if [ ! -x "$WIFI13" ] || ! sh -n "$WIFI13"; then
  fail "wifi-client: runtime missing or invalid"
fi
[ -x "$PROF13" ] || fail "boot-profiler: runtime missing"

# The profiler is one-shot. Run it against a fake timeline and require the
# expected milestone lines, then check that a second run under an active lock
# exits without writing its own BOOT.
PTMP="$TMP/prof"
mkdir -p "$PTMP"
printf '100.0 0\n' > "$PTMP/uptime"
touch "$PTMP/wlan0" "$PTMP/ready"
OPENCMU_PROFILER_LOG="$PTMP/prof.log" OPENCMU_PROFILER_UPTIME="$PTMP/uptime" \
OPENCMU_PROFILER_WLAN="$PTMP/wlan0" OPENCMU_PROFILER_READY_FLAG="$PTMP/ready" \
OPENCMU_PROFILER_WINDOW=2 OPENCMU_PROFILER_STEADY=0 OPENCMU_PROFILER_LOCK="$PTMP/lock" \
  sh "$PROF13"
for _line in BOOT EVENT WIFI_MODULES EVENT WIFI_READY STEADY SNAPSHOT WIFI_UP DONE; do
  grep -qF "$_line" "$PTMP/prof.log" || fail "boot-profiler: log missing '$_line'"
done

# A second run must refuse while the first holds the lock. The first run uses
# an unreachable WLAN to guarantee it stays alive for the whole window.
: > "$PTMP/conc.log"
OPENCMU_PROFILER_LOG="$PTMP/conc.log" OPENCMU_PROFILER_UPTIME="$PTMP/uptime" \
OPENCMU_PROFILER_WLAN="$PTMP/nowhere" OPENCMU_PROFILER_READY_FLAG="$PTMP/nowhere" \
OPENCMU_PROFILER_WINDOW=3 OPENCMU_PROFILER_STEADY=0 OPENCMU_PROFILER_LOCK="$PTMP/lock" \
  sh "$PROF13" &
profpid=$!
sleep 1
OPENCMU_PROFILER_LOG="$PTMP/conc.log" OPENCMU_PROFILER_UPTIME="$PTMP/uptime" \
OPENCMU_PROFILER_WLAN="$PTMP/nowhere" OPENCMU_PROFILER_READY_FLAG="$PTMP/nowhere" \
OPENCMU_PROFILER_WINDOW=1 OPENCMU_PROFILER_STEADY=0 OPENCMU_PROFILER_LOCK="$PTMP/lock" \
  sh "$PROF13"
[ "$(grep -cF 'BOOT' "$PTMP/conc.log")" = "1" ] ||
  fail "boot-profiler: concurrent run wrote a second BOOT"
grep -qF 'another profiler run is active' "$PTMP/conc.log" ||
  fail "boot-profiler: lock collision not reported"
wait "$profpid"
rm -rf "$PTMP"
pass "boot-profiler runtime behaves"

[ "$(head -1 "$SSH13")" = '# [opencmu:enable-ssh] key-only SSH; prepended because the first value wins' ] ||
  fail "enable-ssh: block was not prepended"
[ "$(grep -cF 'opencmu:enable-ssh' "$SSH13")" = "1" ] || fail "enable-ssh: block duplicated"
grep -qF 'PermitRootLogin without-password' "$SSH13" || fail "enable-ssh: root login policy missing"
grep -qF 'PasswordAuthentication no' "$SSH13" || fail "enable-ssh: password auth not disabled"
grep -qF 'Port 22' "$SSH13" || fail "enable-ssh: port 22 missing"
grep -qxF "$(cat "$KEY13")" "$KEYS13" || fail "enable-ssh: key not installed"
[ "$(find "$KEYS13" -perm 600 -print 2>/dev/null)" = "$KEYS13" ] || fail "enable-ssh: key file is not mode 600"

[ "$(find "$WCONF13" -perm 600 -print 2>/dev/null)" = "$WCONF13" ] || fail "wifi-client: config is not mode 600"
( . "$WCONF13"; [ "$WIFI_SSID" = 'OpenCMU Bench' ] && [ "$WIFI_PSK" = 'correct horse battery staple' ]) ||
  fail "wifi-client: config does not round-trip"
grep -qF 'ssid="OpenCMU Bench"' "$WPA13" || fail "wifi-client: ssid missing from wpa config"
grep -qF 'psk="correct horse battery staple"' "$WPA13" || fail "wifi-client: psk missing from wpa config"
pass "ScreenTune-parity batch applies"

run13 --apply --rollback >/dev/null
[ "$(grep -cF 'autorun="no"' "$SM13" || true)" = "0" ] || fail "rollback: services not restored"
[ "$(grep -cF 'affinity_mask="0x02"' "$SM13" || true)" = "0" ] || fail "rollback: affinity left behind"
[ "$(grep -cF 'opencmu:earlier-wifi-init' "$WF13" || true)" = "0" ] || fail "rollback: wifi wait left behind"
[ "$(grep -cF 'opencmu:no-blank-art' "$NP13" || true)" = "0" ] || fail "rollback: artwork patch left behind"
[ "$(grep -cF 'opencmu:order-audio-sources' "$SY13" || true)" = "0" ] ||
  fail "rollback: audio order left behind"
[ "$(grep -cF 'opencmu:select-bt-audio-first' "$SY13" || true)" = "0" ] ||
  fail "rollback: select-bt-audio-first left behind"
grep -qF 'PasswordAuthentication yes' "$SSH13" || fail "rollback: sshd_config not restored"
[ ! -e "$KEYS13" ] || fail "rollback: authorized key left behind"
[ ! -e "$WCONF13" ] || fail "rollback: wifi config left behind"
[ ! -e "$WPA13" ] || fail "rollback: wpa config left behind"
[ ! -e "$TOUCH13" ] || fail "rollback: touchscreen runtime left behind"
[ ! -e "$WIFI13" ] || fail "rollback: wifi client runtime left behind"
[ ! -e "$PROF13" ] || fail "rollback: profiler runtime left behind"
pass "ScreenTune-parity batch rolls back"

# 17b. The new tweaks refuse incomplete or unsafe inputs before writing.
# A refused tweak leaves a receipt behind, so clear the state between attempts.
clean13() {
  rm -f "$FAKE13/data/opencmu/state/receipt.env" \
        "$FAKE13/data/opencmu/state/receipt.json" \
        "$FAKE13/data/opencmu/state/installed.list"
}

if run13 --apply --experimental --tweaks 62-disable-touchscreen >/dev/null 2>&1; then
  fail "disable-touchscreen: ran without the boot hook"
fi
clean13
if OPENCMU_SSH_START=0 sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE13" \
     --apply --experimental --tweaks 75-enable-ssh >/dev/null 2>&1; then
  fail "enable-ssh: ran without a public key"
fi
clean13
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI bench@opencmu\n' > "$TMP/id_ed25519.pub"
if OPENCMU_SSH_PUBKEY="$TMP/id_ed25519.pub" OPENCMU_SSH_START=0 \
   sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE13" \
     --apply --experimental --tweaks 75-enable-ssh >/dev/null 2>&1; then
  fail "enable-ssh: accepted an ed25519 key"
fi
clean13
if OPENCMU_WIFI_PSK='correct horse battery staple' \
   sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE13" \
     --apply --experimental --tweaks 76-enable-wifi-client >/dev/null 2>&1; then
  fail "wifi-client: ran without an SSID"
fi
clean13
if sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE13" \
     --apply --experimental --tweaks 38-order-audio-sources >/dev/null 2>&1; then
  fail "order-audio-sources: ran without OPENCMU_AUDIO_ORDER"
fi
clean13
if OPENCMU_AUDIO_ORDER='BTAudio,NotAStockID' sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" \
     --root "$FAKE13" --apply --experimental --tweaks 38-order-audio-sources >/dev/null 2>&1; then
  fail "order-audio-sources: accepted an unknown source ID"
fi
clean13
if OPENCMU_AUDIO_ORDER='BTAudio,BTAudio' sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" \
     --root "$FAKE13" --apply --experimental --tweaks 38-order-audio-sources >/dev/null 2>&1; then
  fail "order-audio-sources: accepted a repeated source ID"
fi
clean13
pass "SSH and Wi-Fi client require their inputs"

# 17c. Apply once, clear the receipt to bypass the guard, then apply again over
# the patched tree: markers and service counts must not move.
run13 --apply --experimental --tweaks "$PLAN13" >/dev/null
rm -f "$FAKE13/data/opencmu/state/receipt.env" "$FAKE13/data/opencmu/state/receipt.json"
: > "$FAKE13/data/opencmu/state/installed.list"
run13 --apply --experimental --tweaks "$PLAN13" >/dev/null
[ "$(grep -cF 'autorun="no"' "$SM13")" = "18" ] || fail "disable batch duplicated on re-apply"
[ "$(grep -cF 'affinity_mask="0x02"' "$SM13")" = "3" ] || fail "wifi-core duplicated on re-apply"
[ "$(grep -cF 'opencmu:earlier-wifi-init' "$WF13")" = "1" ] || fail "earlier-wifi-init duplicated"
[ "$(grep -cF 'opencmu:no-blank-art' "$NP13")" = "1" ] || fail "no-blank-art duplicated"
[ "$(grep -cF 'opencmu:enable-ssh' "$SSH13")" = "1" ] || fail "enable-ssh duplicated"
[ "$(grep -cF 'opencmu:order-audio-sources' "$SY13")" = "1" ] ||
  fail "order-audio-sources duplicated on re-apply"
[ "$(grep -cF 'opencmu:select-bt-audio-first' "$SY13")" = "1" ] ||
  fail "select-bt-audio-first duplicated on re-apply"
[ "$(wc -l < "$KEYS13" | tr -d ' ')" = "1" ] || fail "enable-ssh: key file grew"
pass "ScreenTune-parity batch is idempotent"

# 17c. Missing anchors and missing services abort without writing.
FAKE14="$TMP/root14"
make_root "$FAKE14"
mkdir -p "$FAKE14/jci/scripts" "$FAKE14/jci/sm" \
         "$FAKE14/jci/gui/common/controls/NowPlaying4/js"
printf '#!/bin/sh\nstart_wifi() { :; }\n' > "$FAKE14/jci/scripts/start_wifi.sh"
printf 'var NowPlaying4Ctrl = function () {};\n' \
  > "$FAKE14/jci/gui/common/controls/NowPlaying4/js/NowPlaying4Ctrl.js"
printf '<service_manager>\n</service_manager>\n' > "$FAKE14/jci/sm/sm.conf"

for spec in \
  "54-wifi-boot-off-busy-core|$FAKE14/jci/sm/sm.conf" \
  "63-no-blank-art|$FAKE14/jci/gui/common/controls/NowPlaying4/js/NowPlaying4Ctrl.js" \
  "74-earlier-wifi-init|$FAKE14/jci/scripts/start_wifi.sh"; do
  tweak=${spec%%|*}
  file=${spec#*|}
  before=$(hash "$file")
  if sh "$PAYLOAD/install.sh" --usb "$PAYLOAD" --root "$FAKE14" \
       --apply --experimental --tweaks "$tweak" >/dev/null 2>&1; then
    fail "$tweak: accepted a missing anchor or service"
  fi
  [ "$(hash "$file")" = "$before" ] || fail "$tweak: wrote after a failed check"
done
pass "new tweaks abort before writing"

# 15. Read-only stock collector.
COLROOT="$TMP/collect/root"
COLUSB="$TMP/collect/usb"
mkdir -p "$COLROOT/jci/gui/apps/system/js" "$COLROOT/etc" "$COLUSB"
: > "$COLUSB/.opencmu-collect"
printf 'JCI_SW_VER=74.00.324\n' > "$COLROOT/jci/version.ini"
printf 'var systemApp = {};\n' > "$COLROOT/jci/gui/apps/system/js/systemApp.js"
printf 'Key = 1\n' > "$COLROOT/etc/dlt.conf"
SBEFORE=$(hash "$COLROOT/jci/gui/apps/system/js/systemApp.js")

OPENCMU_COLLECT_ROOT="$COLROOT" \
OPENCMU_COLLECT_FILES="$ROOT_DIR/builder/collect.files" \
  sh "$ROOT_DIR/builder/collect.sh" "$COLUSB" >/dev/null

DUMP="$COLUSB/opencmu-dump"
[ -f "$DUMP/DONE" ] || fail "collector did not record completion"
[ -f "$DUMP/files/jci/gui/apps/system/js/systemApp.js" ] || fail "collector missed a whitelisted file"
[ -f "$DUMP/files/etc/dlt.conf" ] || fail "collector missed a file outside /jci"
grep -q "  /jci/version.ini\$" "$DUMP/manifest.txt" || fail "collector manifest missing an entry"
grep -q '^MISSING  /jci/gui/framework/js/Websockets.js' "$DUMP/manifest.txt" ||
  fail "collector did not record a missing path"
[ "$(hash "$COLROOT/jci/gui/apps/system/js/systemApp.js")" = "$SBEFORE" ] ||
  fail "collector modified a source file"
pass "stock collector copies read-only"

# 15b. The collector payload carries the on-unit trigger and a checksum list.
if command -v python3 >/dev/null 2>&1; then
  sh "$ROOT_DIR/builder/build-collect.sh" "$TMP/collect-dist" >/dev/null
  [ -f "$TMP/collect-dist/bootstrap.sh" ] || fail "collector payload missing bootstrap.sh"
  [ -f "$TMP/collect-dist/collect.sh" ] || fail "collector payload missing collect.sh"
  [ -f "$TMP/collect-dist/files.txt" ] || fail "collector payload missing files.txt"
  [ -f "$TMP/collect-dist/.opencmu-collect" ] || fail "collector payload missing its marker"
  [ -f "$TMP/collect-dist/SHA256SUMS" ] || fail "collector payload missing SHA256SUMS"
  UPNAME=""
  for f in "$TMP/collect-dist"/*.up; do
    [ -f "$f" ] || continue
    UPNAME=${f##*/}
  done
  [ -n "$UPNAME" ] || fail "collector payload has no .up file"
  case "$UPNAME" in
    */*) fail "collector .up name contains a path separator" ;;
    *'.opencmu-collect'*) : ;;
    *) fail "collector .up name lacks the USB marker lookup" ;;
  esac
  pass "collector payload builds"
fi

printf '\nall tests passed\n'
