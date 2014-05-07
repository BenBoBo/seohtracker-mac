#!/bin/sh

if [ ! -d src ]
then
    cd ..
fi

if [ -d src ]
then
    ~/bin/objctags -R \
        build/nimcache \
        external/ELHASO-mac-snippets \
        external/seohtracker-logic/objc_interface \
        src
fi
