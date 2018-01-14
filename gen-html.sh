#!/bin/bash

FILES="$1"
if [ -z "$FILES" ]
then
	FILES="$(find . -name '*.md')"
fi

ROOT_DIR="$(dirname "$0")"
if [ -z "$ROOT_DIR" ]
then
	ROOT_DIR="."
fi

for FILE in $FILES
do
	pandoc -t html --standalone --self-contained --css "$ROOT_DIR/wording_edits.css" --ascii -o "${FILE%.md}.html" "$FILE"
done
