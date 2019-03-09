#!/bin/sh
# Script to run wine's conformance tests under valgrind
# Usage: ./tools/valgrind/valgrind-full.sh [--fatal-warnings] [--no-exit-hang-hack] [--rebuild] [--skip-crashes] [--skip-failures] [--skip-slow] [--suppress-known] [--virtual-desktop]
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
        printf "%s\\n" "$0: run Wine's conformance tests under Valgrind"
        printf "%s\\n" "Available options:"
        printf "%s\\n" "--count: gives a summary of detected errors and used suppressions"
        printf "%s\\n" "--fatal-warnings: make all Valgrind warnings fatal"
        printf "%s\\n" "--gecko-pdb: use MSVC built pdb debug files for wine-gecko (currently broken)"
        printf "%s\\n" "-h/--help: print this help"
        printf "%s\\n" "--no-exit-hang-hack: disable hack to workaround Wine bug 39097 (enabled by default)"
        printf "%s\\n" "--no-leaks: don't check for memory leaks (disabled by default)"
        printf "%s\\n" "--only-definite-leaks: don't show possible leaks, only definite ones"
        # Doesn't work yet, see:
        # https://bugs.winehq.org/show_bug.cgi?id=46243
        printf "%s\\n" "--progress: have valgrind print statistics every 60s. Requires valgrind-3.14+ (currently broken in Wine)"
        printf "%s\\n" "--rebuild: rebuild Wine before running tests"
        printf "%s\\n" "--skip-crashes: skip any tests that crash under Valgrind"
        printf "%s\\n" "--skip-failures: skip any tests that fail under Valgrind"
        printf "%s\\n" "--skip-slow: skip tests that fail on slow machines"
        printf "%s\\n" "--suppress-known: suppress known bugs in Wine"
        printf "%s\\n" "--verbose: use valgrind verbose mode (-v -v -v) instead of --quiet"
        printf "%s\\n" "--virtual-desktop: run tests in a virtual desktop"
}

exit_hang_hack=1
fatal_warnings=""
gecko_pdb=0
leak_check="--leak-check=full"
leak_style=""
rebuild_wine=0
skip_crashes=0
skip_failures=0
skip_slow=0
suppress_known=""
verbose_mode="-q"
virtual_desktop=""

gecko_version="2.36"
wine_version="$(git describe origin/master)"

# Must be run from the wine tree
WINESRC="${WINESRC:-$HOME/wine-valgrind}"
# Prepare for calling winetricks
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-valgrind}"
export WINE="$WINESRC/wine"
# Convenience variable
WINESERVER="$WINESRC/server/wineserver"

# Choose which version of valgrind you want to use:
export WINETEST_WRAPPER="${WINETEST_WRAPPER:-/opt/valgrind/bin/valgrind}"
#export WINETEST_WRAPPER=valgrind
#export WINETEST_WRAPPER=$HOME/src/valgrind/vg-in-place

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
# FIXME: we don't support win64 yet, so hardcoding win32 for now:
winbit="win32"
_time="$(command -v time)"

mkdir -p "${WINESRC}/logs"
logfile="${WINESRC}/logs/${wine_version}-${winbit}-${os}-${arch}.log"

while [ -n "$1" ] ; do
    arg="$1"
    shift
    case "${arg}" in
        -h|--help) usage; exit 0;;
        # FIXME: Add an option to not skip any tests (move touch foo to a wrapper, check for variable, make no-op and log it)
        --count) count="--show-error-list=yes";;
        --fatal-warnings) fatal_warnings="--error-exitcode=1";;
        --gecko-pdb) gecko_pdb=1;;
        --no-exit-hang=hack) exit_hang_hack=0;;
        --no-leaks) leak_check="--leak-check=no";;
        --only-definite-leaks) leak_style="--show-leak-kinds=definite";;
        # Doesn't work yet, see:
        # https://bugs.winehq.org/show_bug.cgi?id=46243
        --progress) progress="--progress-interval=60";;
        --rebuild) rebuild_wine=1;;
        --skip-crashes) skip_crashes=1;;
        --skip-failures) skip_failures=1;;
        --skip-slow) skip_slow=1;;
        --suppress-known) suppress_known="--suppressions=${WINESRC}/tools/valgrind/valgrind-suppressions-gecko --suppressions=${WINESRC}/tools/valgrind/valgrind-suppressions-known-bugs";;
        --verbose) verbose_mode="-v -v -v";;
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

if test ! -f "${WINESRC}/configure"; then
    echo "couldn't find ${WINESRC}/configure"
    exit 1
fi

# We grep error messages, so make them all English
LANG=C

if [ -f "${WINESERVER}" ]; then
    "${WINESERVER}" -k || true
fi
rm -rf "${WINEPREFIX}"

# Build a fresh wine, if desired/needed:
if [ ! -f Makefile ] || [ "$rebuild_wine" = "1" ]; then
    make distclean || true

    if [ $exit_hang_hack = 1 ]; then
        # revert 4a1629c4117fda9eca63b6f56ea45771dc9734ac
        # See https://bugs.winehq.org/show_bug.cgi?id=39097
        sed -i -e 's!_exit( exit_code )!exit( exit_code )!g' "${WINESRC}/dlls/ntdll/process.c"
    fi

    ./configure CFLAGS="-g -ggdb -Og -fno-inline"
    "$_time" make -j"$(nproc)"
fi

# Run wineboot under valgrind, and remove the prefix (just in case that corrupts things)
echo "================Running wineboot under valgrind================" >> "$logfile"
"$WINETEST_WRAPPER" ./wine wineboot
echo "================End of wineboot================" >> "$logfile"

$WINESERVER -w

echo "================Removing wineprefix ($WINEPREFIX)================" >> "$logfile"
rm -rf "$WINEPREFIX"
echo "================wineprefix $WINEPREFIX removed================" >> "$logfile"

# Disable the crash dialog and enable heapchecking
if [ ! -f winetricks ] ; then
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

if [ $gecko_pdb -eq 1 ]; then
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
# ddraw/ddraw7 (in wine-4.1-108-gf7b3120991/bumblebee): General Protection Fault, but only with primusrun, optirun works fine
touch dlls/ddraw/tests/ddraw7.ok # https://bugs.kde.org/show_bug.cgi?id=264785
touch dlls/ddraw/tests/ddrawmodes.ok # test crashes https://bugs.winehq.org/show_bug.cgi?id=26130 / https://bugs.kde.org/show_bug.cgi?id=264785
touch dlls/kernel32/tests/thread.ok # valgrind crash https://bugs.winehq.org/show_bug.cgi?id=28817 / https://bugs.kde.org/show_bug.cgi?id=335563
touch dlls/kernel32/tests/virtual.ok # valgrind assertion failure after https://bugs.winehq.org/show_bug.cgi?id=28816: valgrind: m_debuginfo/debuginfo.c:1261 (vgPlain_di_notify_pdb_debuginfo): Assertion 'di && !di->fsm.have_rx_map && !di->fsm.have_rw_map' failed.
touch dlls/kernel32/tests/virtual.ok # https://bugs.winehq.org/show_bug.cgi?id=43352 infinite loop under valgrind
touch dlls/msvcrt/tests/string.ok # valgrind wontfix: https://bugs.winehq.org/show_bug.cgi?id=36165

# hangs with patch reverted (in 2.19) (FIXME retest in 4.0)
touch dlls/ieframe/tests/ie.ok # hangs with 1% usage

# makes a stray explorer process that prevents make test from exiting
# https://bugs.winehq.org/show_bug.cgi?id=46380
touch dlls/user32/tests/winstation.ok

if [ $exit_hang_hack = 0 ]; then
    # These are caused by 4a1629c4117fda9eca63b6f56ea45771dc9734ac
    # https://bugs.winehq.org/show_bug.cgi?id=39097
    # FIXME: should just run a sed here to turn _exit to exit in dlls/ntdll/process.c, for now; easier than reverting cleanly
    # FIXME: note if it's 0% or 100% CPU usage when hung

    echo "======================================"
    echo "disabling hanging bugs"

    #touch dlls/dsound/tests/duplex.ok # FIXME: hangs
    #touch dlls/mshtml/tests/htmldoc.ok # FIXME: hangs
    #touch dlls/mshtml/tests/htmllocation.ok # FIXME: hangs
    #touch dlls/ole32/tests/clipboard.ok # FIXME: hangs
    #touch dlls/ole32/tests/marshal.ok # FIXME: hangs

    touch dlls/comdlg32/tests/filedlg.ok # FIXME
    touch dlls/comdlg32/tests/itemdlg.ok # FIXME
    touch dlls/crypt32/tests/chain.ok # FIXME
    touch dlls/dbghelp/tests/dbghelp.ok # FIXME
    touch dlls/dinput8/tests/device.ok # hangs with 1% usage
    touch dlls/mmdevapi/tests/propstore.ok # FIXME
    touch dlls/mmdevapi/tests/mmdevenum.ok # FIXME
    touch dlls/mmdevapi/tests/render.ok # hangs with 0.2% usage
    touch dlls/msvcp140/tests/msvcp140.ok # FIXME
    touch dlls/ole32/tests/dragdrop.ok # FIXME
    touch dlls/ole32/tests/moniker.ok # FIXME
    touch dlls/ole32/tests/ole_server.ok # hangs with 1% usage
    touch dlls/oleaut32/tests/usrmarshal.ok # hangs with 0% usage
    touch dlls/qmgr/tests/enum_files.ok # hangs with 1% usage
    touch dlls/qmgr/tests/enum_jobs.ok # hangs with 0% usage
    touch dlls/qmgr/tests/file.ok # hangs with 1.8% usage
    touch dlls/qmgr/tests/job.ok # hangs with 1% usage
    touch dlls/riched20/tests/editor.ok # hangs with 1% usage
    touch dlls/rpcrt4/tests/ndr_marshall.ok # hangs with 0.1% usage
    touch dlls/shell32/tests/ebrowser.ok # hangs with 0% usage
    touch dlls/shell32/tests/shlview.ok # hangs with 0% usage
    touch dlls/urlmon/tests/sec_mgr.ok # hangs with 1% usage
    touch dlls/user32/tests/sysparams.ok # hangs with 1% usage
    touch dlls/vcomp/tests/vcomp.ok # hangs with 1% usage

    # FIXME next time one fails, see if lsof shows what's open still
    # FIXME: are there more?
    echo "======================================"
fi

# These only hang on my (arm32) chromebook:
if [ "$arch" = "armv7l" ]; then
    touch dlls/comctl32/tests/imagelist.ok # hangs
    touch dlls/comctl32/tests/toolbar.ok # 10m errors
    touch dlls/comctl32/tests/treeview.ok # hangs
    touch dlls/crypt32/tests/cert.ok # max error
    touch dlls/crypt32/tests/encode.ok # hangs
    touch dlls/d3d8/tests/visual.ok # hangs
    touch dlls/d3d9/tests/d3d9ex.ok # hangs

    touch dlls/imm32/tests/imm32.ok # hangs
    touch dlls/kernel32/tests/file.ok # hangs
    touch dlls/msacm32/tests/msacm.ok # hangs
    touch dlls/msvcirt/tests/msvcirt.ok # 10m errors
    touch dlls/msvcp140/tests/msvcp140.ok # 10m errors
    touch dlls/msvcp90/tests/misc.ok # valgrind bug (unhandled instruction), FIXME, file bug
    touch dlls/msvcr100/tests/msvcr100.ok # 10m errors
    touch dlls/ntdll/tests/file.ok # hangs
    touch dlls/ntdll/tests/info.ok # 10m errors
    touch dlls/ntdll/tests/time.ok # hangs
    touch dlls/oleaut32/tests/safearray.ok # hangs
    touch dlls/oleaut32/tests/tmarshal.ok # hangs
    touch dlls/rpcrt4/tests/cstub.ok # makes a gajillion unrecognized symbol errors (all ???)
    touch dlls/user32/tests/class.ok # 10m errors
    touch dlls/user32/tests/menu.ok # hangs (FIXME there's a bug in test, hangs when submenu is waiting for a mouse click. Clicking bypasses it, but skipping for now)
    touch dlls/vcomp/tests/vcomp.ok # hangs (actually, process was sleeping?)
    touch dlls/wininet/tests/http.ok # 10m errors
    touch dlls/ws2_32/tests/sock.ok # hangs

    # Things that fail without gecko (FIXME: move to own exclusion, enable for arm):
    touch dlls/ieframe/tests/webbrowser.ok # hangs
    touch dlls/mshtml/tests/xmlhttprequest.ok # hangs
    touch dlls/msxml3/tests/xmlview.ok # hangs

    # Things that fail without mono (FIXME ^):
    touch dlls/mscoree/tests/metahost.ok # hangs
    touch dlls/mscoree/tests/mscoree.ok # hangs
fi

# wine bugs:
touch dlls/winmm/tests/mci.ok # https://bugs.winehq.org/show_bug.cgi?id=30557

# wine hangs with pdb debug builds in dlls/ieframe/tests/ie.c (https://bugs.winehq.org/show_bug.cgi?id=38604)
# and (sometimes) in dlls/atl100/tests/atl.c (https://bugs.winehq.org/show_bug.cgi?id=38594)
if [ $gecko_pdb -eq 1 ]; then
    touch dlls/atl100/tests/atl.ok
    touch dlls/ieframe/tests/ie.ok
fi

if [ $skip_crashes -eq 1 ]; then
    touch dlls/crypt32/tests/msg.ok # crashes https://bugs.winehq.org/show_bug.cgi?id=36200
    touch dlls/d2d1/tests/d2d1.ok # crashes https://bugs.winehq.org/show_bug.cgi?id=38481
    touch dlls/d3d8/tests/device.ok # test crashes https://bugs.winehq.org/show_bug.cgi?id=28800
    touch dlls/d3dx9_36/tests/mesh.ok # test fails on intel/nvidia https://bugs.winehq.org/show_bug.cgi?id=28810
    touch dlls/ddraw/tests/d3d.ok # test crashes on nvidia https://bugs.winehq.org/show_bug.cgi?id=36660
    touch dlls/ddrawex/tests/surface.ok # valgrind segfaults on nvidia https://bugs.winehq.org/show_bug.cgi?id=36689 / https://bugs.kde.org/show_bug.cgi?id=335907
    touch dlls/kernel32/tests/debugger.ok # intentional
    touch dlls/ntdll/tests/exception.ok # https://bugs.winehq.org/show_bug.cgi?id=28735
    touch dlls/user32/tests/dde.ok # https://bugs.winehq.org/show_bug.cgi?id=39257

    # FIXME: if video card detection is added, need to block a lot on intel/bumblebee https://bugs.winehq.org/show_bug.cgi?id=46321
fi

if [ $skip_failures -eq 1 ]; then
    # Virtual desktop failures:
    if [ -n "$virtual_desktop" ]; then
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

if [ $skip_slow -eq 1 ]; then
    # sample times (/usr/bin/time) for the program test on my i7-7820HQ laptop:
    # cmd:      0:53:45 elapsed
    # regedit:  2:23:03 elapsed
    # reg:      3:23:01 elapsed
    # schtasks: 0:05:50 elapsed
    # services: 0:00:30 elapsed
    # wscript:  0:01:50 elapsed
    # xcopy:    0:04:47 elapsed

    # https://bugs.winehq.org/show_bug.cgi?id=36672
    touch dlls/kernel32/tests/debugger.ok
    # 2.5 hours:
    touch programs/regedit/tests/regedit.ok
    # 3.5 hours:
    touch programs/reg/tests/reg.ok
fi

# Finally run the tests:
export VALGRIND_OPTS="$verbose_mode --trace-children=yes --track-origins=yes --gen-suppressions=all --suppressions=$WINESRC/tools/valgrind/valgrind-suppressions-external --suppressions=$WINESRC/tools/valgrind/valgrind-suppressions-ignore $suppress_known $fatal_warnings $leak_check $leak_style --num-callers=20 $progress --workaround-gcc296-bugs=yes --vex-iropt-register-updates=allregs-at-mem-access $count"
export WINE_HEAP_TAIL_REDZONE=32

"$_time" sh -c "make -k test 2>&1 | tee \"$logfile\" || true"

# Kill off winemine and any stragglers
"$WINESERVER" -k || true

if [ -n "$count" ]; then
    echo "======================================================================="
    echo "Used suppressions:" >> "$logfile"
    grep used_suppression "$logfile" | cut -d / -f 1 | awk '{print $NF}' | sort -u
    echo "======================================================================="

    # FIXME: parse $VAGLRIND_OPTS for --suppression,
    # grep -A 1 \{ (this won't work if there are comments though :/)
    # and compare with `comm` to used_suppressions, for a list of unused ones for review
    # Also maybe suppress _ignore list unless -v is used
fi

# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
