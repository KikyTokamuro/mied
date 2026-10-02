#!/bin/sh
#
# Mied - build a standalone binary for Linux or macOS with tclexecomp.
#
# The editor, its icon, its language files, and the license are copied into
# build/wrap/, wrapped with tclexecomp -forcewrap, and the finished binary is
# moved to dist/.
#
# See the "Building a standalone binary" section of the README for details.

set -eu

NAME="mied"
COMPILE=1
CLEAN=0
TOOL="${TCLEXECOMP:-}"

usage() {
    cat <<'EOF'
Build a standalone Mied binary for Linux or macOS with tclexecomp.

Usage: scripts/build-unix.sh [options]

  --no-compile    ship readable Tcl instead of bytecode
  --clean         remove build/ and dist/ before building
  --tool <path>   tclexecomp driver binary to run (default: tclexecomp64,
                  or tclexecomp64.mac on macOS)
  --name <name>   name of the output binary (default: mied)
  -h, --help      show this help

TCLEXECOMP sets the --tool default.
EOF
}

die() {
    printf 'build-unix: %s\n' "$1" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case $1 in
        --no-compile) COMPILE=0 ;;
        --clean)      CLEAN=1 ;;
        --tool)       shift; [ $# -gt 0 ] || die "--tool needs a path"; TOOL=$1 ;;
        --name)       shift; [ $# -gt 0 ] || die "--name needs a value"; NAME=$1 ;;
        -h|--help)    usage; exit 0 ;;
        *)            die "unknown option '$1' (try --help)" ;;
    esac
    shift
done

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK="$ROOT/build"
WRAP="$WORK/wrap"
DIST="$ROOT/dist"

[ -f "$ROOT/mied.tcl" ] || die "mied.tcl not found in $ROOT"
[ -f "$ROOT/img/icon.png" ] || die "img/icon.png not found in $ROOT"
[ -f "$ROOT/LICENSE" ] || die "LICENSE not found in $ROOT"
[ -d "$ROOT/langs" ] || die "langs directory not found in $ROOT"

# The host platform decides the driver: the stock binaries are tclexecomp64
# for Linux and tclexecomp64.mac for macOS.
OS=$(uname -s 2>/dev/null || echo unknown)
if [ -z "$TOOL" ]; then
    case $OS in
        Darwin) TOOL=tclexecomp64.mac ;;
        *)      TOOL=tclexecomp64 ;;
    esac
fi
command -v "$TOOL" >/dev/null 2>&1 \
    || die "tclexecomp driver '$TOOL' not found, pass --tool <path>"
TOOL=$(CDPATH= cd -- "$(dirname -- "$(command -v "$TOOL")")" && pwd)/$(basename -- "$TOOL")

# The driver doubles as the stub that -w points at, and the stub's extension
# is what tclexecomp appends to the output name (tclexecomp64.mac → mied.mac).
STUB=$TOOL

if [ "$CLEAN" -eq 1 ]; then
    rm -rf "$WORK" "$DIST"
fi
# Always rebuild the wrap directory: tclexecomp copies whatever is in it.
rm -rf "$WORK"
mkdir -p "$WRAP/img" "$WRAP/langs" "$DIST"

cp "$ROOT/mied.tcl"     "$WRAP/mied.tcl"
cp "$ROOT/img/icon.png" "$WRAP/img/icon.png"
cp "$ROOT/LICENSE"      "$WRAP/LICENSE"
cp "$ROOT"/langs/*.lang "$WRAP/langs/"

# Bytecode keeps the source out of the binary, at the cost of needing tbcload
# in the stub. tclexecomp writes mied.tbc next to the script; the howto then
# renames it to mied.tcl, since the wrapped file is plain "source"d at startup.
if [ "$COMPILE" -eq 1 ]; then
    printf 'Compiling mied.tcl to bytecode...\n'
    ( cd "$WORK" && "$TOOL" -compile wrap/mied.tcl )
    if [ -f "$WRAP/mied.tbc" ]; then
        mv -f "$WRAP/mied.tbc" "$WRAP/mied.tcl"
    elif [ -f "$WORK/mied.tbc" ]; then
        mv -f "$WORK/mied.tbc" "$WRAP/mied.tcl"
    else
        die "bytecode was not produced, rerun with --no-compile"
    fi
fi

# tclexecomp wants the main script first and every wrapped file listed too.
# Paths stay relative to build/ ("wrap/...") because the leading "wrap/" is
# stripped when the start file is mounted, which is what puts the output
# binary in build/ instead of build/wrap/.
set -- wrap/mied.tcl
while IFS= read -r file; do
    [ -n "$file" ] && set -- "$@" "$file"
done <<EOF
$(cd "$WORK" && find wrap -type f ! -name mied.tcl | sort)
EOF

printf 'Wrapping for %s...\n' "$OS"
( cd "$WORK" && "$TOOL" "$@" -forcewrap -w "$STUB" -appname "$NAME" -o "$NAME" )

# macOS stubs are named tclexecomp64.mac, so the binary comes out as mied.mac.
case $OS in
    Darwin) OUT="$WORK/$NAME.mac" ;;
    *)      OUT="$WORK/$NAME" ;;
esac
if [ ! -f "$OUT" ]; then
    for candidate in "$WORK/$NAME".*; do
        [ -f "$candidate" ] && OUT=$candidate
    done
fi
[ -f "$OUT" ] || die "tclexecomp did not produce $OUT"

# A failed wrap leaves the plain stub behind, so a binary that is not bigger
# than the stub means the payload never made it in.
stub_size=$(wc -c < "$STUB" | tr -d ' ')
out_size=$(wc -c < "$OUT" | tr -d ' ')
[ "$out_size" -gt "$stub_size" ] || die \
    "the wrap step failed: $OUT ($out_size bytes) is not bigger than the stub ($stub_size bytes)"

mv -f "$OUT" "$DIST/"
DEST="$DIST/$(basename -- "$OUT")"
chmod +x "$DEST"

printf 'Built %s (%s)\n' "${DEST#$ROOT/}" "$(du -h "$DEST" | cut -f1)"
