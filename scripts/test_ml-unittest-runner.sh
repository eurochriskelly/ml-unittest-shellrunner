#!/bin/bash

# Check that user has passed in the correct number of arguments
if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <path-to-cup-repo> [<after-test-number>]"
    exit 1
fi
dir=$1
after_test_number=1
if [ -n "$2" ]; then
    after_test_number=$2
fi
if [ ! -d "$dir" ]; then
    echo "Error: $dir does not exist"
    exit 1
fi

bash scripts/run_unit_tests.sh \
  --directory $dir \
  --test_port 8043 \
  --after $after_test_number
