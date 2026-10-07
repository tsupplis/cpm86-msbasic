#!/bin/sh
# Normalise a BASIC session transcript so two interpreters can be diffed:
# drop the sign-on banner (everything up to "Bytes free", when there is one),
# blank lines, lines holding only a number (free memory figures differ between
# builds) and the clock (dates and times).
awk '{ l[NR] = $0 } /Bytes free/ && !b { b = NR }
     END { for (i = b + 1; i <= NR; i++) print l[i] }' |
sed -E -e '/^ *$/d' -e 's/^ *[0-9][0-9]* *$/<num>/' \
    -e 's/[0-9]{2}-[0-9]{2}-[0-9]{4}/<date>/g' -e 's/[0-9]{2}:[0-9]{2}(:[0-9]{2})?/<time>/g'
