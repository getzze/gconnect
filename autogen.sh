#!/bin/sh

# Calling this script is basically the same as calling the configure
# script directly, except that if your project uses submodules calling
# this script will automatically initialize them.

if [ -e $(dirname "$0")/.gitmodules ]; then
    (cd "$(dirname "$0")" && git submodule update --init --recursive)
fi

$(dirname $0)/configure "$@"
