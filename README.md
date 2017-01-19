# wine-valgrind
Scripts and valgrind suppressions for Wine

Based on Dan Kegel's original scripts, available at https://code.google.com/p/winezeug/source/browse/trunk/valgrind/

Before starting, make sure that this directory is available as tools/valgrind (in the wine source tree, a symlink is fine)

You'll also want valgrind installed (optionally, compile from source and use the patches provided for better stacktraces)

Suppression files:
There are 4 provided suppression files:
* valgrind-suppressions-external: issues in external projects (glibc, libpng, nvidia/mesa drivers, etc.) (enabled by default)
* valgrind-suppressions-gecko: issues in wine-gecko  (disabled by default)
* valgrind-suppressions-ignore: issues in wine that are intentional  (enabled by default)
* valgrind-suppressions-known-bugs: known issues in wine that are not yet fixed (disabled by default)

To run the entire test suite under valgrind, use valgrind-full:
Usage: ./tools/valgrind/valgrind-full.sh [--fatal-warnings] [--rebuild] [--skip-crashes] [--skip-failures] [--skip-slow] [--suppress-known] [--virtual-desktop]

all arguments are optional:
* --fatal-warnings: if valgrind finds a problem, valgrind will report it as an error instead of a warning
* --rebuild: rebuild wine before running the tests
* --skip-crashes: skip tests that are known to crash under valgrind
* --skip-failures: skip tests that are known to fail
* --skip-slow: skip tests that fail on slow machines
* --suppress-known: suppress all known wine issues
* --virtual-desktop: run the tests in a virtual desktop

to run a single test under valgrind, you can use vg-wrapper.sh (which just sets the proper variables). To do so, open two terminals:
term1: ./wine notepad
term2: . tools/valgrind/vg-wrapper.sh && cd dlls/msi/tests && make action.ok
