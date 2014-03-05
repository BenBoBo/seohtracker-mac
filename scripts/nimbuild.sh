#!/bin/sh

# Force errors to fail script.
set -e

# DONT CHANGE THESE INITIAL VARIABLES!
# Use the override file to modify them, so git doesn't complain about changes.

# Set this to the full path of your nimrod compiler
# since Xcode doesn't inherit your user environment.
PATH_TO_NIMROD=~/project/nimrod/root/bin/nimrod

# Set this to the location of the nimbase.h file so
# the script can update it if it changes.
PATH_TO_NIMBASE=~/project/nimrod/root/lib/nimbase.h

# Where the nimrod source lives.
NIMSRC=src/nim

# Path to the google analytics config not under source control.
GOOGLE=build/google_analytics_config.h

# If we are running from inside the scripts subdir, get out.
if [ ! -d "$NIMSRC" ]
then
    cd ..
fi

# This is the override file. You can create it and override the above values.
# The override file is not under source control, so git won't complain about
# changes.
test -s scripts/nimbuild_options.sh && . scripts/nimbuild_options.sh

# Verify executable bit for binaries.
if [ ! -x "$PATH_TO_NIMROD" ]; then
    echo "Nimrod compiler not found at '$PATH_TO_NIMROD'"
    echo "Get it from http://nimrod-lang.org"
    exit 1
fi

if [ ! -s "$PATH_TO_NIMBASE" ]; then
    echo "nimbase.h not found at '$PATH_TO_NIMBASE'"
    echo "Get it from https://github.com/Araq/Nimrod"
    exit 1
fi

NIMOUT="../../build/nimcache" # Relative to NIMSRC
DEST_NIMBASE="${NIMOUT}/nimbase.h"

if [[ "${ACTION}" == "clean" ]]; then
    echo "Cleaning ${NIMOUT}"
    rm -Rf "${NIMOUT}"
    exit 0
fi

# Ok, are we out now?
if [ -d "$NIMSRC" ]
then
    mkdir -p "${NIMSRC}/${NIMOUT}"

    # Make sure the google analytics code header exists, though maybe empty.
    if [[ ! -f "${GOOGLE}" ]]; then
        touch "${GOOGLE}"
    fi

    # Force doc regeneration
    if [[ nakefile.nim -nt nakefile ]]; then
        "${PATH_TO_NIMROD}" c -r nakefile doc
    else
        ./nakefile doc
    fi

    # Generate icons.
    ./nakefile icons

    if [[ "${CONFIGURATION}" == "Release" ]]; then
        FLAGS="-d:mac -d:release"
    else
        FLAGS="-d:mac"
    fi

    # Build library for ios.
    cd "$NIMSRC"
    $PATH_TO_NIMROD objc --noMain  --app:lib \
        --nimcache:"${NIMOUT}" --verbosity:0 --compileOnly \
        --header ${FLAGS} n_global.nim
    # Update nimbase for ios.
    if [ "${PATH_TO_NIMBASE}" -nt "${DEST_NIMBASE}" ]
    then
        echo "Updating nimbase.h"
        cp "${PATH_TO_NIMBASE}" "${DEST_NIMBASE}"
    fi
    ## Build standalone binary for commandline testing when not under xcode.
    #if [[ -z "${XCODE_PRODUCT_BUILD_VERSION}" ]]; then
    #    $PATH_TO_NIMROD c --parallelBuild:1 --nimcache:build/nimcache2 \
    #        "$NIMSRC"/n_global.nim && mv "$NIMSRC"/n_global seohyun
    #fi
    echo "Finished compiling nimrod code."
else
    echo "Uh oh, $NIMSRC directory not found?"
    exit 1
fi
