#!/bin/bash
#

# Check that user has passed in the correct number of arguments
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path-to-cup-repo>"
    exit 1
fi

dir=$1
if [ ! -d "$dir" ]; then
    echo "Error: $dir does not exist"
    exit 1
fi

export MLU_PORT_TEST=8043

bash scripts/run_unit_tests.sh --directory $dir
