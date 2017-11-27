#!/bin/sh
# Script to run wine's conformance tests under valgrind
# Usage: ./tools/valgrind/valgrind-full.sh [--fatal-warnings] [--rebuild] [--skip-crashes] [--skip-failures] [--skip-slow] [--suppress-known] [--virtual-desktop]
#
# Copyright: 2014-2017 Austin English <austinenglish@gmail.com>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA
#
# Based on Dan Kegel's original scripts: https://code.google.com/p/winezeug/source/browse/trunk/valgrind/

set -x
set -e

# Note: if building on Gentoo, make sure -march=* is not in global CFLAGS, see
# https://bugs.kde.org/show_bug.cgi?id=380869

usage() {
        printf "%s\n" "$0: run Wine's conformance tests under Valgrind"
        printf "%s\n" "Available options:"
        printf "%s\n" "--fatal-warnings: make all Valgrind warnings fatal"
        printf "%s\n" "--gecko-pdb: use MSVC built pdb debug files for wine-gecko (currently broken)"
        printf "%s\n" "-h/--help: print this help"
        printf "%s\n" "--only-definite-leaks: don't show possible leaks, only definite ones"
        printf "%s\n" "--rebuild: rebuild Wine before running tests"
        printf "%s\n" "--skip-crashes: skip any tests that crash under Valgrind"
        printf "%s\n" "--skip-failures: skip any tests that fail under Valgrind"
        printf "%s\n" "--skip-slow: skip tests that fail on slow machines"
        printf "%s\n" "--suppress-known: suppress known bugs in Wine"
        printf "%s\n" "--virtual-desktop: run tests in a virtual desktop"
}

fatal_warnings=""
gecko_pdb=0
rebuild_wine=0
skip_crashes=0
skip_failures=0
skip_slow=0
suppress_known=""
virtual_desktop=""
leak_style=""

gecko_version="2.36"
wine_version="$(git describe origin/master)"

# Must be run from the wine tree
WINESRC="$HOME/wine-valgrind"
# Prepare for calling winetricks
export WINEPREFIX="$HOME/.wine-valgrind"
export WINE="$WINESRC/wine"
# Convenience variable
WINESERVER="$WINESRC/server/wineserver"

# Choose which version of valgrind you want to use:
export WINETEST_WRAPPER=/opt/valgrind/bin/valgrind
#WINETEST_WRAPPER=valgrind

# In theory, wine + valgrind can work on (at least):
# win32/linux86 (worked a long time ago, haven't tested recently)
# win32/linux64 (works, usual platform)
# win64/linux64 (works, not frequently tested)
# win32/macosx (doesn't work) # https://bugs.kde.org/show_bug.cgi?id=349804
# win64/macosx (doesn't work) # https://bugs.kde.org/show_bug.cgi?id=349804
# win32/solaris86 (untested)
# win32/solaris64 (untested)
# win32/arm32 (semi works, a lot of hanging tests and other issues)
# win64/arm64 (seems to work, only lightly tested)
#
# So we need arch/os to:
# A) distinguish logs
# B) allow for platform specific workarounds/bugs

arch="$(uname -m)"
os="$(uname -s)"

mkdir -p "${WINESRC}/logs"
logfile="${WINESRC}/logs/${wine_version}-${os}-${arch}.log"

while [ ! -z "$1" ] ; do
    arg="$1"
    shift
    case "${arg}" in
        -h|--help) usage; exit 0;;
        # FIXME: Add an option to not skip any tests (move touch foo to a wrapper, check for variable, make no-op and log it)
        --fatal-warnings) fatal_warnings="--error-exitcode=1";;
        --gecko-pdb) gecko_pdb=1;;
        --only-definite-leaks) leak_style="--show-leak-kinds=definite";;
        --rebuild) rebuild_wine=1;;
        --skip-crashes) skip_crashes=1;;
        --skip-failures) skip_failures=1;;
        --skip-slow) skip_slow=1;;
        --suppress-known) suppress_known="--suppressions=${WINESRC}/tools/valgrind/valgrind-suppressions-gecko --suppressions=${WINESRC}/tools/valgrind/valgrind-suppressions-known-bugs";;
        --virtual-desktop|--vd) virtual_desktop="vd=1024x768";;
        *) echo "invalid option $arg passed!"; usage; exit 1;;
    esac
done

# disable BSTR cache
export OANOCACHE=1

# reduce spam:
export WINEDEBUG=-all

echo "started with: $0 $*" > "$logfile"

# shellcheck disable=SC2129
echo "HEAD is:" >> "$logfile"
git log -n 1 HEAD >> "$logfile"

echo "origin/master is:" >> "$logfile"
git log -n 1 origin/master >> "$logfile"

echo "git log between origin/master and HEAD:" >> "$logfile"
git log origin/master..HEAD >> "$logfile"

echo "git diff between origin/master and HEAD:" >> "$logfile"
git diff origin/master HEAD >> "$logfile"

# Valgrind only reports major version info (or -SVN, but no rev #, to get that, use -v):
# https://bugs.kde.org/show_bug.cgi?id=352395
echo "Using $(${WINETEST_WRAPPER} -v --version)" >> "$logfile"

cd "${WINESRC}"

if test ! -f "${WINESRC}/configure"
then
    echo "couldn't find ${WINESRC}/configure"
    exit 1
fi

# We grep error messages, so make them all English
LANG=C

if [ -f "${WINESERVER}" ]
then
    "${WINESERVER}" -k || true
fi
rm -rf "${WINEPREFIX}"

# Build a fresh wine, if desired/needed:
if test ! -f Makefile || test "$rebuild_wine" = "1"
then
    make distclean || true
    ./configure CFLAGS="-g -O0 -fno-inline"
    time make -j4
fi

# Disable the crash dialog and enable heapchecking
if test ! -f winetricks
then
    wget http://winetricks.org/winetricks
fi

# Only enable a virtual desktop if specified on the command line:
sh winetricks nocrashdialog heapcheck $virtual_desktop

# Mingw built debug dlls don't work right now (https://bugs.winehq.org/show_bug.cgi?id=36463 )
# Aside from that, valgrind doesn't support mingw built binaries well (https://bugs.kde.org/show_bug.cgi?id=211031)
#if test ! -f wine_gecko-${gecko_version}-x86-unstripped.tar.bz2
#then
#    wget http://downloads.sourceforge.net/project/wine/Wine%20Gecko/${gecko_version}/wine_gecko-${gecko_version}-x86-unstripped.tar.bz2
#fi

if [ $gecko_pdb -eq 1 ]
then
    if test ! -f wine_gecko-${gecko_version}-x86-dbg-msvc-pdb.tar.bz2
    then
        wget http://downloads.sourceforge.net/project/wine/Wine%20Gecko/${gecko_version}/wine_gecko-${gecko_version}-x86-dbg-msvc-pdb.tar.bz2
    fi

    if test ! -f wine_gecko-${gecko_version}-x86-dbg-msvc.tar.bz2
    then
        wget http://downloads.sourceforge.net/project/wine/Wine%20Gecko/${gecko_version}/wine_gecko-${gecko_version}-x86-dbg-msvc.tar.bz2
    fi

    tar xjmvf "$WINESRC/wine_gecko-${gecko_version}-x86-dbg-msvc-pdb.tar.bz2" -C "${WINEPREFIX}/drive_c"

    cd "${WINEPREFIX}/drive_c/windows/system32/gecko/${gecko_version}"
    rm -rf wine_gecko
    tar xjmvf "${WINESRC}/wine_gecko-${gecko_version}-x86-dbg-msvc.tar.bz2"
    cd "${WINESRC}"
fi

# make sure our settings took effect:
$WINESERVER -w

# start a minimized winemine to avoid repeated startup penalty even though that hides some errors
# Note: running `wineserver -p` is not enough, because that only runs wineserver, not any services
# FIXME: suppressions for wine's default services:
$WINE start /min winemine

# start fresh:
make testclean

# valgrind bugs:
# FIXME: ddraw stuff should be checked, may be driver bugs?
touch dlls/ddraw/tests/ddraw1.ok # https://bugs.kde.org/show_bug.cgi?id=264785
touch dlls/ddraw/tests/ddraw2.ok # https://bugs.kde.org/show_bug.cgi?id=264785
touch dlls/ddraw/tests/ddraw4.ok # valgrind assertion failure https://bugs.winehq.org/show_bug.cgi?id=36261
touch dlls/ddraw/tests/ddraw7.ok # https://bugs.kde.org/show_bug.cgi?id=264785
touch dlls/ddraw/tests/ddrawmodes.ok # test crashes https://bugs.winehq.org/show_bug.cgi?id=26130 / https://bugs.kde.org/show_bug.cgi?id=264785
touch dlls/kernel32/tests/thread.ok # valgrind crash https://bugs.winehq.org/show_bug.cgi?id=28817 / https://bugs.kde.org/show_bug.cgi?id=335563
touch dlls/kernel32/tests/virtual.ok # valgrind assertion failure after https://bugs.winehq.org/show_bug.cgi?id=28816: valgrind: m_debuginfo/debuginfo.c:1261 (vgPlain_di_notify_pdb_debuginfo): Assertion 'di && !di->fsm.have_rx_map && !di->fsm.have_rw_map' failed.
touch dlls/msvcrt/tests/string.ok # valgrind wontfix: https://bugs.winehq.org/show_bug.cgi?id=36165

# hanging bugs:
touch dlls/comdlg32/tests/filedlg.ok # FIXME: hangs, need bug
touch dlls/comdlg32/tests/itemdlg.ok # FIXME: hangs, need bug
touch dlls/dinput8/tests/device.ok # FIXME: hangs, need bug
touch dlls/dsound/tests/duplex.ok # FIXME: hangs, need bug
touch dlls/ieframe/tests/ie.ok # FIXME: hangs, need bug
touch dlls/kernel32/tests/virtual.ok # https://bugs.winehq.org/show_bug.cgi?id=43352 infinite loop under valgrind
touch dlls/mshtml/tests/events.ok # https://bugs.winehq.org/show_bug.cgi?id=37157 hangs under valgrind
touch dlls/mshtml/tests/htmldoc.ok # FIXME: hangs
touch dlls/mshtml/tests/htmllocation.ok # FIXME: hangs
touch dlls/ole32/tests/clipboard.ok # FIXME: hangs
touch dlls/ole32/tests/marshal.ok # FIXME: hangs
touch dlls/user32/tests/win.ok # https://bugzilla.redhat.com/show_bug.cgi?id=1248314

# wine bugs:
touch dlls/winmm/tests/mci.ok # https://bugs.winehq.org/show_bug.cgi?id=30557

# wine hangs with pdb debug builds in dlls/ieframe/tests/ie.c (https://bugs.winehq.org/show_bug.cgi?id=38604)
# and (sometimes) in dlls/atl100/tests/atl.c (https://bugs.winehq.org/show_bug.cgi?id=38594)
if [ $gecko_pdb -eq 1 ]
then
    touch dlls/atl100/tests/atl.ok
    touch dlls/ieframe/tests/ie.ok
fi

if [ $skip_crashes -eq 1 ]
then
    touch dlls/crypt32/tests/msg.ok # crashes https://bugs.winehq.org/show_bug.cgi?id=36200
    touch dlls/d2d1/tests/d2d1.ok # crashes https://bugs.winehq.org/show_bug.cgi?id=38481
    touch dlls/d3d8/tests/device.ok # test crashes https://bugs.winehq.org/show_bug.cgi?id=28800
    touch dlls/d3dx9_36/tests/mesh.ok # test fails on intel/nvidia https://bugs.winehq.org/show_bug.cgi?id=28810
    touch dlls/ddraw/tests/d3d.ok # test crashes on nvidia https://bugs.winehq.org/show_bug.cgi?id=36660
    touch dlls/ddrawex/tests/surface.ok # valgrind segfaults on nvidia https://bugs.winehq.org/show_bug.cgi?id=36689 / https://bugs.kde.org/show_bug.cgi?id=335907
    touch dlls/kernel32/tests/debugger.ok # intentional
    touch dlls/ntdll/tests/exception.ok # https://bugs.winehq.org/show_bug.cgi?id=28735
    touch dlls/user32/tests/dde.ok # https://bugs.winehq.org/show_bug.cgi?id=39257
    touch dlls/wbemprox/tests/query.ok # https://bugs.winehq.org/show_bug.cgi?id=43354
fi

if [ $skip_failures -eq 1 ]
then
    # Virtual desktop failures:
    if [ ! -z $virtual_desktop ]
    then
        touch dlls/comctl32/tests/propsheet.ok # https://bugs.winehq.org/show_bug.cgi?id=36238
        touch dlls/user32/tests/win.ok # https://bugs.winehq.org/show_bug.cgi?id=36682 win.c:2244: Test succeeded inside todo block: GetActiveWindow() = 0x1200c4
    fi

    touch dlls/d3d8/tests/visual.ok # https://bugs.winehq.org/show_bug.cgi?id=35862 visual.c:13837: Test failed: Expected color 0x000000ff, 0x000000ff, 0x00ff00ff or 0x00ff7f00 for instruction "rcp1", got 0x00ff0000 (nvidia)
    touch dlls/d3d9/tests/device.ok # https://bugs.kde.org/show_bug.cgi?id=335563 device.c:3587: Test failed: cw is 0xf7f, expected 0xf60.
    touch dlls/d3d9/tests/visual.ok # https://bugs.winehq.org/show_bug.cgi?id=35862 visual.c:13837: Test failed: Expected color 0x000000ff, 0x000000ff, 0x00ff00ff or 0x00ff7f00 for instruction "rcp1", got 0x00ff0000.
    touch dlls/gdi32/tests/font.ok # https://bugs.winehq.org/show_bug.cgi?id=36234 font.c:3607: Test succeeded inside todo block: W: tmFirstChar for Mathematica1 got 00 expected 00
    touch dlls/gdiplus/tests/font.ok # https://bugs.winehq.org/show_bug.cgi?id=28097 font.c:784: Test failed: wrong face name Liberation Sans
    touch dlls/kernel32/tests/heap.ok # https://bugs.winehq.org/show_bug.cgi?id=36673 heap.c:1138: Test failed: 0x10: got heap flags 00000002 expected 00000020
    touch dlls/kernel32/tests/loader.ok # test fails https://bugs.winehq.org/show_bug.cgi?id=28816 https://bugs.winehq.org/show_bug.cgi?id=28816
    touch dlls/kernel32/tests/pipe.ok # https://bugs.winehq.org/show_bug.cgi?id=35781 / https://bugs.winehq.org/show_bug.cgi?id=36071 pipe.c:612: Test failed: overlapped ConnectNamedPipe
    touch dlls/kernel32/tests/process.ok # https://bugs.winehq.org/show_bug.cgi?id=28220 process.c:1356: Test failed: Getting sb info
    touch dlls/kernel32/tests/thread.ok # https://bugs.kde.org/show_bug.cgi?id=335563 thread.c:1460: Test failed: Expected FPU control word 0x27f, got 0x37f.
    touch dlls/mmdevapi/tests/capture.ok # https://bugs.winehq.org/show_bug.cgi?id=36674
    touch dlls/mshtml/tests/htmldoc.ok # https://bugs.winehq.org/show_bug.cgi?id=36563 htmldoc.c:2528: Test failed: unexpected call UpdateUI
    touch dlls/oleaut32/tests/olepicture.ok # https://bugs.winehq.org/show_bug.cgi?id=36710 olepicture.c:784: Test failed: Color at 10,10 should be unchanged 0x000000, but was 0x140E11
    touch dlls/oleaut32/tests/vartype.ok # test fails https://bugs.winehq.org/show_bug.cgi?id=28820
    touch dlls/shell32/tests/shlexec.ok # https://bugs.winehq.org/show_bug.cgi?id=36678 shlexec.c:139: Test failed: ShellExecute(verb="", file=""C:\users\austin\Temp\wt952f.tmp\drawback_file.noassoc foo.shlexec"") WaitForSingleObject returned 258
    touch dlls/urlmon/tests/protocol.ok # https://bugs.winehq.org/show_bug.cgi?id=36675 protocol.c:329: Test failed: dwResponseCode=0, expected 200
    touch dlls/user32/tests/menu.ok # https://bugs.winehq.org/show_bug.cgi?id=36677
    touch dlls/user32/tests/msg.ok # https://bugs.winehq.org/show_bug.cgi?id=36586 msg.c:11369: Test failed: expected -32000,-32000 got 21,714
    touch dlls/user32/tests/winstation.ok # https://bugs.winehq.org/show_bug.cgi?id=36676 / https://bugs.winehq.org/show_bug.cgi?id=36587
    touch dlls/wininet/tests/http.ok # https://bugs.winehq.org/show_bug.cgi?id=36637
    touch dlls/ws2_32/tests/sock.ok # https://bugs.winehq.org/show_bug.cgi?id=36681 sock.c:2270: Test failed: Expected 10047, received 10043
    touch programs/xcopy/tests/xcopy.ok # https://bugs.winehq.org/show_bug.cgi?id=36172
fi

if [ $skip_slow -eq 1 ]
then
    touch dlls/kernel32/tests/debugger.ok # https://bugs.winehq.org/show_bug.cgi?id=36672
fi

# Finally run the tests:
export VALGRIND_OPTS="-q --trace-children=yes --track-origins=yes --gen-suppressions=all --suppressions=$WINESRC/tools/valgrind/valgrind-suppressions-external --suppressions=$WINESRC/tools/valgrind/valgrind-suppressions-ignore $suppress_known $fatal_warnings --leak-check=full $leak_style --num-callers=20  --workaround-gcc296-bugs=yes --vex-iropt-register-updates=allregs-at-mem-access"
export WINETEST_TIMEOUT=600
export WINE_HEAP_TAIL_REDZONE=32

time make -k test >> "$logfile" 2>&1 || true

# Kill off winemine and any stragglers
"$WINESERVER" -k || true

# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
