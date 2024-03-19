# General Unit Testing Script Guide

This document details how to use a bash script designed for running unit tests,
especially in the context of MarkLogic database environments. The script
efficiently manages system resources, particularly memory, by monitoring usage
and performing server restarts as necessary. While it can be integrated into a
CI/CD pipeline, its design allows for versatile use in any environment
requiring automated testing and resource management.

## Overview

The script automates the execution of unit tests against a MarkLogic server,
tracks memory usage before and after each test suite to ensure optimal
performance, and initiates server restarts when memory thresholds are exceeded.
This proactive resource management is crucial in maintaining system stability
and performance during intensive testing sessions.

## Prerequisites

- Bash shell
- MarkLogic server access
- Installed `curl` and `xmlstarlet` for HTTP requests and XML processing
- Appropriate permissions for the executing user to perform tests and server restarts on MarkLogic

## Running the Script

### Basic execution
To execute the script:

    bash scripts/run_unit_tests.sh \
      --directory /path/to/ml-repository-to-test \
      --test_port 8123

Default test port is 8010 and default directory is the current directory

### Example: run all tests from number 10 onwards

    bash scripts/run_unit_tests.sh \
      --directory /path/to/ml-repository-to-test \
      --test_port 8123 \
      --after 10

## Output

The script provides detailed output for each test suite, including test results
and memory usage before and after execution. This output is designed for
clarity and ease of use, not just for CI/CD environments but for any context
where detailed feedback on test performance and resource usage is valuable.

In case of test failures or significant memory usage increases, the script
ensures that appropriate actions are taken, including server restarts and
detailed logging, to assist in identifying and resolving issues.


