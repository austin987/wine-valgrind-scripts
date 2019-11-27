#!/bin/bash
#
# Copyright: 2019 Austin English <austinenglish@gmail.com>
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

# Check wine's bugzilla to see if any bugs are resolved:

bug_list="$(grep ' bug_' valgrind-suppressions-* | cut -d _ -f2 | sort -u)"

tmpdir="$(mktemp -d)"
cd "$tmpdir" || exit 1

echo "Downloading bug reports, this may take a bit"
for bug in $bug_list; do
    curl -s -o "$bug" "https://bugs.winehq.org/show_bug.cgi?ctype=xml&id=${bug}"
done

echo "The following bugs are resolved upstream:"
# Note: we only check known-bugs which is what we really care about:
grep '<resolution>' ./valgrind-suppressions-known-bugs | grep -v '><'

rm -rf "$tmpdir"
