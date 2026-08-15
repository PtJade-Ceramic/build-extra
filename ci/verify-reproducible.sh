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
			diff -u "$extract_a" "$extract_b" 2>/dev/null |
				grep -E '^[+-]' | sed -n '1,20p' >&2 || true
			;;
		*)
			# first differing byte offset (and octal byte values), if any
			cmp -l "$extract_a" "$extract_b" 2>/dev/null | sed -n '1p' |
				awk '{ printf "  first diff at byte %s (a=%s b=%s)\n", $1, $2, $3 }' >&2 || true
			# PE-level diagnostics (binutils objdump/objcopy may be absent)
			if type -p objdump >/dev/null 2>&1 && type -p objcopy >/dev/null 2>&1
			then
				for side in a b
				do
					if test "$side" = a; then f="$extract_a"; else f="$extract_b"; fi
					echo "  [$side] PE: $(objdump -p "$f" 2>/dev/null | grep -E 'TimeDateStamp|SizeOfImage|SizeOfHeaders|CheckSum|Debug' | tr '\n' ';')" >&2
					echo "  [$side] sec: $(objdump -h "$f" 2>/dev/null | awk 'NR>5 {printf "%s=%s ", $2, $3}')" >&2
				done
				for sec in .rsrc .rdata
				do
					objcopy -O binary --only-section="$sec" "$extract_a" /tmp/sec.a.$$ 2>/dev/null || continue
					objcopy -O binary --only-section="$sec" "$extract_b" /tmp/sec.b.$$ 2>/dev/null || continue
					sa=$(wc -c </tmp/sec.a.$$)
					sb=$(wc -c </tmp/sec.b.$$)
					if ! cmp -s /tmp/sec.a.$$ /tmp/sec.b.$$
					then
						echo "  [$sec] section differs: a=$sa b=$sb bytes" >&2
						# First differing byte (1-based). cmp -l prints nothing
						# for a pure length difference (EOF on the shorter
						# file), so detect that case explicitly.
						if off=$(cmp -l /tmp/sec.a.$$ /tmp/sec.b.$$ 2>/dev/null | sed -n '1s/[[:space:]].*//p')
						then
							:
						fi
						if test -n "$off"
						then
							start=$((off - 16))
							test "$start" -lt 1 && start=1
							for side in a b
							do
								if test "$side" = a; then f=/tmp/sec.a.$$; else f=/tmp/sec.b.$$; fi
								echo "  [$side][$sec] @$off $(od -An -tx1 -j $((start - 1)) -N 32 "$f" 2>/dev/null | tr -d '\n')" >&2
							done
						else
							echo "  [$sec] content prefix identical; length differs by $((sa - sb)) bytes (EOF on the shorter file)" >&2
						fi
						# Show the tail of both sections (resource data that
						# differs only near EOF is common).
						ta=$((sa > 48 ? sa - 48 : 0))
						tb=$((sb > 48 ? sb - 48 : 0))
						echo "  [$sec] tail a: $(od -An -tx1 -j "$ta" /tmp/sec.a.$$ 2>/dev/null | tr -d '\n')" >&2
						echo "  [$sec] tail b: $(od -An -tx1 -j "$tb" /tmp/sec.b.$$ 2>/dev/null | tr -d '\n')" >&2
						if test "$sa" -gt "$sb"
						then
							echo "  [$sec] a has $((sa - sb)) trailing bytes: $(od -An -tx1 -j "$sb" -N $((sa - sb)) /tmp/sec.a.$$ 2>/dev/null | tr -d '\n')" >&2
						elif test "$sb" -gt "$sa"
						then
							echo "  [$sec] b has $((sb - sa)) trailing bytes: $(od -An -tx1 -j "$sa" -N $((sb - sa)) /tmp/sec.b.$$ 2>/dev/null | tr -d '\n')" >&2
						fi
					fi
					rm -f /tmp/sec.a.$$ /tmp/sec.b.$$
				done
			fi
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
