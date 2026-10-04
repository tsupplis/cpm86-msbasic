#!/bin/sh
# Normalise a BASIC session transcript so two interpreters can be diffed:
# drop the sign-on banner, blank lines, lines holding only a number (free
# memory figures differ between builds) and the clock (dates and times).
sed -E -e '1,/Bytes free/d' -e '/^ *$/d' -e 's/^ *[0-9][0-9]* *$/<num>/' \
    -e 's/[0-9]{2}-[0-9]{2}-[0-9]{4}/<date>/g' -e 's/[0-9]{2}:[0-9]{2}(:[0-9]{2})?/<time>/g'
