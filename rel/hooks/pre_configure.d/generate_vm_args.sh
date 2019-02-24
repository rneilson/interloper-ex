#!/usr/bin/env bash
# hooks/pre_configure.d/generate_vm_args.sh

export REPLACE_OS_VARS=true

export NODENAME="${NODENAME:-interloper_ex}"
export HOSTNAME="${HOSTNAME:-$(hostname -f)}"

export COOKIE

if [[ -z "$COOKIE" ]]; then
    COOKIE='xMud7ox+KRvtM0dDAbBqyowAl354ds/8tmk2B8QT/PsC69QVErj0svcf4g63wyyh'
fi
