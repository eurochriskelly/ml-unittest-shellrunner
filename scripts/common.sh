#!/bin/bash

# DESCRIPTION:
#
# Jobs must be able to check that all required environment variables are set
#
mandatoryEnv() {
    local envVar=
    for envVar in "$@"; do
        if [ -z "${!envVar}" ]; then
            rr "ERROR: Environment variable [$envVar] is not set"
            printEnvironment
            exit 1
        else
            echo "    Mandatory variable [$envVar] is set to [${!envVar}]"
        fi
    done
}

getPod() {
    kubectl get pods -l app="cup-$1" -o jsonpath="{.items[0].metadata.name}"
}

testeroo() {
    echo "I shall testeroo too. In $1"
}

# Print out (almost) all environment variables
printEnvironment() {
    yy "===== POD ENV: BEGIN ====="
    excluded_prefixes="APPLICATIE_|CUP_BLAPI_|CUP_DEPLOYER_|CUP_MARKLOGIC_|KUBERNETES_|PYTHON_"
    excluded_vars="CHARSET|OLDPWD|LANG|PATH|NSS_SDB_USE_CACHE|LC_COLLATE|GPG_KEY|LDAP_GROUP_DN|HOME|LDAP_GROUP_DN|PWD|TZ|TERM|SOPS_VERSION|SHLVL|_"
    printenv | sort | uniq | awk -F"=" -v p="$excluded_prefixes" -v v="$excluded_vars" 'BEGIN { count=0 } !($1 ~ "^("p")") && !($1 ~ "^("v")$") { count++; printf "%4d %-30s %s\n", count, $1, $2 }'
    yy "===== POD ENV: END ====="
}

# Loggers with date formatted like this: 2020-01-01T12:00:00 hard-coded using % in date command
dd() { echo "  DD $(date +%Y-%m-%dT%H:%M:%S): $@"; }
ii() { echo -e "  \033[33mII $(date +%Y-%m-%dT%H:%M:%S): $@\033[0m"; } #YELLOW
ee() { echo "  EE $(date +%Y-%m-%dT%H:%M:%S): $@" 1>&2; }
ww() { echo "  WW $(date +%Y-%m-%dT%H:%M:%S): $@" 1>&2; }
hh() { echo -e "\033[35m>    $(date +%Y-%m-%dT%H:%M:%S): $@ \033[0m"; } #MAGENTA
rr() { echo -e "\033[31m$@\033[0m"; }                                   #RED
bb() { echo -e "\033[34m$@\033[0m"; }                                   #BLUE
yy() { echo -e "\033[33m$@\033[0m"; }                                   #YELLOW

# send arguments encoded in case they break the command
decodeArgs() {
    local decoded_args=()
    for arg in "$@"; do
        case $arg in
        --args=*)
            local ARGS="${arg#*=}"
            ARGS=$(echo "$ARGS" | base64 --decode)
            decoded_args+=($ARGS)
            ;;
        *)
            decoded_args+=("$arg")
            ;;
        esac
    done
    # Set "$@" to the decoded arguments
    set -- "${decoded_args[@]}"
}
