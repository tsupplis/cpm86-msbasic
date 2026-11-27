#!/bin/sh
# Ignore the startup banner and the build-dependent result of PRINT FRE(0).
# emu2's CP/M clock reads host time after T_SET. Mask only the three
# clock reads in the current CP/M dostime session, never echoed literals.
awk -v clock="${1:-}" '
    { lines[NR] = $0 }
    !started && NF { started = 1; heading = /^(Microsoft BASIC Version|BASIC-86 Rev[.])/ }
    heading && /^ *[0-9]+ Bytes free *$/ { banner = NR; heading = 0 }
    END {
        for (i = banner + 1; i <= NR; i++) {
            line = lines[i]
            if (line ~ /^ *$/) continue
            if (memory && line ~ /^ *[0-9]+ *$/) line = "<free memory>"
            if (clock == "cpm-dostime") {
                if (previous ~ /^date\$="(01-02-2020|1\/2\/20)":print date\$$/ &&
                    line ~ /^[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]$/) line = "<date>"
                if (previous == "time$=\"10:20:30\":print left$(time$,5)" &&
                    line ~ /^[0-9][0-9]:[0-9][0-9]$/) line = "<time>"
            }
            previous = tolower(line)
            memory = (tolower(line) == "print fre(0)")
            print line
        }
    }'
