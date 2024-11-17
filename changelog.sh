#!/bin/bash
# generate changelog text

# read version information
. version.sh

# and just output to NOTES.txt
echo "BASH ${BASH_VERSION}-$(printf '%03d' $BASH_PATCH_LEVEL), with MUSL ${MUSL_VERSION}" > NOTES.txt