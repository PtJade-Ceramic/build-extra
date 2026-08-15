#!/bin/sh
#
# Compare two build outputs and report whether they are byte-identical.
# Used by the reproducible-build verification workflow (this branch only;
# not part of the shipped artifacts).
#
# Usage:
#   verify-reproducible.sh --dir <a> <b>
#       compare every file (or symlink) under directory <a> with its
#       counterpart under <b>, by name and by content
#   verify-reproducible.sh --pkg <a.tar.xz> <b.tar.xz>
#       compare the members of two Pacman package archives by name and
#       by content (directory members are ignored)
#
# Exits 0 if identical, 1 if any difference is found. Differences are
# reported with diagnostics (sizes, first differing byte offset) to help
# distinguish e.g. embedded timestamps from content drift.

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
extract_a=/tmp/verify-reproducible.xa.$$
extract_b=/tmp/verify-reproducible.xb.$$
fail=0

list_files () { # <arg> <outfile>
	case "$mode" in
	dir)
		(cd "$1" && find . \( -type f -o -type l \) -print | sed 's|^\./||' | sort) \
			>"$2"
		;;
	pkg)
		# directory members end in '/' and carry no content of their own
		tar -tf "$1" 2>/dev/null | sed -n '\#/$#!p' | sort >"$2"
		;;
	esac
}

extract_member () { # <arg> <member> <outfile>
	case "$mode" in
	dir)
		cat "$1/$2" >"$3" 2>/dev/null
		;;
	pkg)
		tar -xOf "$1" "$2" >"$3" 2>/dev/null
		;;
	esac
}

list_files "$a" "$tmp_a"
list_files "$b" "$tmp_b"

if ! cmp -s "$tmp_a" "$tmp_b"
then
	echo "FAIL: member/file list differs:" >&2
	diff -u "$tmp_a" "$tmp_b" >&2 || true
	fail=1
fi

while IFS= read -r f
do
	test -n "$f" || continue
	extract_member "$a" "$f" "$extract_a"
	extract_member "$b" "$f" "$extract_b"
	if ! cmp -s "$extract_a" "$extract_b"
	then
		echo "DIFF: $f" >&2
		echo "  sha256: a=$(sha256sum "$extract_a" 2>/dev/null | cut -d' ' -f1) b=$(sha256sum "$extract_b" 2>/dev/null | cut -d' ' -f1)" >&2
		echo "  size: a=$(wc -c <"$extract_a" 2>/dev/null) b=$(wc -c <"$extract_b" 2>/dev/null)" >&2
		case "$f" in
		.MTREE|.PKGINFO)
			diff -u "$extract_a" "$extract_b" 2>/dev/null | sed -n '1,25p' >&2 || true
			;;
		*)
			# first differing byte offset (and octal byte values), if any
			cmp -l "$extract_a" "$extract_b" 2>/dev/null | sed -n '1p' |
				awk '{ printf "  first diff at byte %s (a=%s b=%s)\n", $1, $2, $3 }' >&2 || true
			;;
		esac
		fail=1
	fi
done <"$tmp_a"

rm -f "$tmp_a" "$tmp_b" "$extract_a" "$extract_b"

if test "$fail" = 0
then
	echo "PASS: '$a' and '$b' are identical"
else
	echo "FAIL: differences found" >&2
	exit 1
fi
