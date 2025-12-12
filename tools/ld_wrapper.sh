#!/bin/bash
# Wrapper around ld to fix __DATA_CONST segment issues on macOS Sequoia

# Find the real linker
REAL_LD="/usr/bin/ld"

# Call the real linker with all arguments
"$REAL_LD" "$@"
RESULT=$?

# If linking succeeded, try to fix the output binary
if [ $RESULT -eq 0 ]; then
    # Find the output file (-o argument)
    OUTPUT=""
    for ((i=1; i<=$#; i++)); do
        if [ "${!i}" == "-o" ]; then
            ((i++))
            OUTPUT="${!i}"
            break
        fi
    done

    # If we found an output file and it's an executable, try to fix it
    if [ -n "$OUTPUT" ] && [ -f "$OUTPUT" ]; then
        # Try to ad-hoc sign it which sometimes helps
        codesign -s - -f "$OUTPUT" 2>/dev/null || true
    fi
fi

exit $RESULT
