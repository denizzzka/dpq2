#!/bin/bash
set -ev

dub test

if [ "$DC" == "dmd" ]
then
    #dub run dscanner -- -s #disable due to stall
    #dub run dscanner -- -S #disabled due to assertion failure in dsymbol
    dub run dpq2:integration_tests --build=unittest-cov -- --conninfo="${1}"
    dub run dpq2:example --build=release -- --conninfo="${1}"
else
    dub run dpq2:integration_tests --build=unittest -- --conninfo="${1}"
fi
