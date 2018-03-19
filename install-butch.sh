#!/bin/sh
INSTALLDIR=/usr/local/bin

for i in awk wget sha512sum; do
	if ! which "$i" >/dev/null 2>&1 ; then
		echo "error: prerequisite $i not found in PATH" >&2
		exit 1
	fi
done

mkdir -p "$INSTALLDIR"
cp -v ./KEEP/bin/* "$INSTALLDIR/"

