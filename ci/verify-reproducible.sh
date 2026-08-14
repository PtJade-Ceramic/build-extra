#!/bin/sh
#
# Compare two build outputs and report whether they are byte-identical.
# Used by the reproducible-build verification workflow (this branch only;
# not part of the shipped artifacts).
#
# Usage:
#   verify-reproducible.sh --dir <a> <b>
#       compare every file (or symlink) under directory <a> with its
#       counterpart under <b>, by name and by SHA-256
#   verify-reproducible.sh --pkg <a.tar.xz> <b.tar.xz>
#       compare the members of two Pacman package archives by name and
#       by SHA-256 of each member's content
#
# Exits 0 if identical, 1 if any difference is found.

die () {
	echo "$*" >&2
	exit 1
}

case "$1" in
--dir) mode=dir;;
--pkg) mode=pkg;;
*) die "Usage: $0 (--dir <a> <b> | --pkg <a.tar.xz> <b.tar.xz>)";;
esac
shift
test $# -eq 2 || die "Need exactly two arguments"
a=$1
b=$2
test -e "$a" || die "No such path: $a"
test -e "$b" || die "No such path: $b"

tmp_a=/tmp/verify-reproducible.a.$$
tmp_b=/tmp/verify-reproducible.b.$$
fail=0

list_files () { # <dir> <outfile>
	(cd "$1" && find . \( -type f -o -type l \) -print | sed 's|^\./||' | sort) \
		>"$2"
}

case "$mode" in
dir)
	list_files "$a" "$tmp_a"
	list_files "$b" "$tmp_b"
	;;
pkg)
	tar -tf "$a" | sort >"$tmp_a"
	tar -tf "$b" | sort >"$tmp_b"
	;;
esac

if ! cmp -s "$tmp_a" "$tmp_b"
then
	echo "FAIL: member/file list differs:" >&2
	diff -u "$tmp_a" "$tmp_b" >&2 || true
	fail=1
fi

compare_member () { # <path>
	case "$mode" in
	dir)
		(cd "$a" && sha256sum "$1" 2>/dev/null)
		(cd "$b" && sha256sum "$1" 2>/dev/null)
		;;
	pkg)
		tar -xOf "$a" "$1" 2>/dev/null | sha256sum
		tar -xOf "$b" "$1" 2>/dev/null | sha256sum
		;;
	esac
}

while IFS= read -r f
do
	test -n "$f" || continue
	ha=$(compare_member "$f" | sed -n '1p' | cut -d' ' -f1)
	hb=$(compare_member "$f" | sed -n '2p' | cut -d' ' -f1)
	if test -z "$ha" || test -z "$hb" || test "$ha" != "$hb"
	then
		echo "DIFF: $f" >&2
		fail=1
	fi
done <"$tmp_a"

rm -f "$tmp_a" "$tmp_b"

if test "$fail" = 0
then
	echo "PASS: '$a' and '$b' are identical"
else
	echo "FAIL: differences found" >&2
	exit 1
fi
