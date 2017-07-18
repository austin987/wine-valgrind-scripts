#!/bin/bash
set -x

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

# Strip down wine/valgrind logs to just the valgrind info:
orig_file="$1"

grep -h -v \
    -e 'GnuTLS error:' \
    -e 'LOAD_PDB_DEBUGINFO: Find PDB file:' \
    -e make \
    -e ^preloader: \
    -e 'Test failed' \
    -e 'Tests skipped' \
    -e 'Test succeeded' \
    -e 'Warning: Missing or un-stat-able' \
    -e 'regedit: Unrecognized escape sequence' \
    "${orig_file}" > "${orig_file}.stripped"

echo "Cleaned up ${orig_file} as ${orig_file}.stripped"
