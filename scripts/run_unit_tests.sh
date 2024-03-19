#!/bin/base
#
# This should run the unit tests and determine if they have passed or failed.
# The output must be visible in the gitlab ci interface.
#
set -e

main() {
	hh "Running unit tests ..."
	processArgs "$@"
	init
	banner
	restartMarkLogic 2>&1 >/dev/null # quietly restart
	# get starting memory after restart
	local startingFreeMemory=$(getFreeMemory)

	echo "  TIME  SUITE                                                                                               ERRS FAIL  TOTAL       TIME  USED  FREE"
	local startTimer=$(date +%s)

	local limit=$MLU_LIMIT

	local testSuiteData=$(getTestSuites)
	if [[ $testSuiteData != \<t:tests* ]]; then
		rr "  ERROR: no tests found in call to ${TEST_URL}?func=list"
		echo "---"
		head -n 5 "$testSuiteData" | sed 's/^/  /'
		echo "---"
		exit 1
	fi
	limit=1000

	testNr=$AFTER # starting test number
	echo "$testSuiteData" |
		xmlstarlet sel -t -m "//t:suite" -v "@path" -n |
		head -n $limit |
		awk -v line_num="$AFTER" 'NR >= line_num' |
		while read -r suite; do
			memBefore=$(getFreeMemory)
			executeTestSuite "$suite" | while read -r line; do
				memAfter=$(getFreeMemory)
				memUsage=$((memBefore - memAfter))
				# total time so far in seconds
				local now=$(date +%s)
				local elapsed=$((now - startTimer)) # seconds
				# Display as a fix width string of 5 characters
				local elapsedStr=$(printf "%5s" "$elapsed")
				# echo "$(tput cuu1)$(tput el) $elapsedStr $line $memUsage"
				su=$(echo $memUsage | awk '{printf "%5.0f\n", $1/1000}')
				sa=$(echo $memAfter | awk '{printf "%5.0f\n", $1/1000}')
				echo ""
				echo -n " $elapsedStr $line $su $sa"
				# After displaying the summary, stop the test if there are failures
				if [ -f "$STOP_ON_FAIL" ]; then break; fi
			done

			if [ -f "$STOP_ON_FAIL" ]; then
				echo ""
				echo "  WARNING: UNIT TEST FAILURE (test #${testNr}). Please fix. See LOG message below for details."
				rm -f "$STOP_ON_FAIL"
				echo "------ LOG ------"
				cat $LOG
				echo "------ LOG ------"
				exit 1
				break
			fi
			testNr=$((testNr + 1))
			# require if we are using 6GB more than when we started
			if [ "$(($startingFreeMemory - $(getFreeMemory)))" -gt "6000000" ]; then
				restartMarkLogic
			fi
		done
	echo ""
	echo "ALL TEST SUITES PASSED!"
}

testRun() {
	clear
	source config/cicd/pipeline/variables-local.sh
	main "$@"
}

## IMPL
{
	init() {
		MGMT_URL="${PROTOCOL}://${MAIN_HOST}:${PORT_MLMANAGE}"
		BASE_URL="${PROTOCOL}://${MAIN_HOST}:${PORT_TEST}"
		TEST_URL="${BASE_URL}/test/default.xqy"
	}

	banner() {
		echo "-----------------------------------------------------"
		echo "          M A R K L O G I C       T E S T S          "
		echo "-----------------------------------------------------"
		echo ""
	}

	# Query the memory on the server. Do no use meters since it is not always available.
	# As documented, MarkLogic relies on /proc/meminfo to get the memory usage.
	getFreeMemory() {
		local scr='fn:tokenize(fn:tokenize(xdmp:filesystem-file("/proc/meminfo"), "\n")[2], " ")[fn:last() - 1]'
		while true; do
			res=$(curl -s -k --digest --user "$TESTER_USER:$TESTER_PASS" \
				--data-urlencode "xquery=$scr" "${MGMT_URL}/v1/eval" | tail -n 2 | head -n 1 | awk '{print $1}')
			local freeMem=$(echo "$res" | tr -cd '[[:digit:]]')
			if [ -n "$freeMem" ]; then
				echo $freeMem
				break
			fi
			sleep 1
		done
	}

	# Restart on demand
	restartMarkLogic() {
		local now=$(date +%s)
		curl \
			-s -k --digest --user "$TESTER_USER:$TESTER_PASS" \
			-X POST -H "Content-Type: application/json" \
			-d '{"operation":"restart-local-cluster"}' \
			${MGMT_URL}/manage/v2 2>&1 >/dev/null
		waitForMarkLogic
		echo -n " -> restart $(($(date +%s) - now))s"
	}

	# wait for marklogic to be ready. Handle service down and
	# service being installed.
	# TODO: make this a common function
	waitForMarkLogic() {
		local ALIVE_HOST="${PROTOCOL}://$MAIN_HOST:7997"
		local waitingForMarklogic=true
		local i=0
		local res=""
		while $waitingForMarklogic; do
			# Use curl to check the MarkLogic healthcheck endpoint
			res=$(curl -I "$ALIVE_HOST" 2>/dev/null | grep HTTP | tr -d '\r')
			if [ -n "$res" ]; then
				# check for a 200 response
				res=$(echo "$res" | { grep "200" || true; } 2>/dev/null)
				if [ -n "$res" ]; then
					break
				else
					echo "non getting 200 response from [$ALIVE_HOST]"
				fi
				echo "no response from [$ALIVE_HOST]"
			fi
			sleep 1
			i=$(($i + 1))
		done
		sleep 5
	}

	executeTestSuite() {
		local suite="$1"
		local target="${TEST_URL}?func=run&suite=$suite&format=junit&runsuiteteardown=true&runteardown=true"
		## 1. RUN THE TEST SUITE
		res=$(curl -s \
			--user "$TESTER_USER:$TESTER_PASS" \
			--digest "$target")

		# 2. Make a nice summary
		echo "$res" | xmlstarlet sel \
			-t -m "//testsuite" \
			-v "@name" -o " " \
			-v "@errors" -o " " \
			-v "@failures" -o " " \
			-v "@tests" -o " " \
			-v "format-number(@time, '0.0')" -n |
			awk '{ printf "%-100s %4s %4s %6s %10s\n", $1, $2, $3, $4, $5 }'

		# 3. Check if there were any errors or failures so we can exit early
		local errs=$(echo "$res" | xmlstarlet sel \
			-t -m "//testsuite" \
			-v "@errors")

		local fails=$(echo "$res" | xmlstarlet sel \
			-t -m "//testsuite" \
			-v "@failures")

		: "${errs:=0}"
		: "${fails:=0}"

		if [ "$errs" -gt "0" ] || [ "$fails" -gt "0" ]; then
			touch $STOP_ON_FAIL

			# Use xmlstarlet to parse the XML and extract the test name and failure contents
			test_name=$(echo "$res" | xmlstarlet sel -t -m "//failure" -v "../@name" -n)
			failure_contents=$(echo "$res" | xmlstarlet sel -T -t -m "//failure" -v "." -n)

			# Remove <error:stack> element from failure_contents
			failure_contents=$(echo "$failure_contents" | xmlstarlet ed --delete "//error:stack")

			# Format failure_contents into proper XML

			# Format the output and write to the log file
			echo -e "   Test Name: $test_name" >>$LOG
			echo -e "   Failure Contents:" >>$LOG
			echo "" >>$LOG
			echo "$failure_contents" | xmlstarlet fo --indent-tab >>$LOG
			echo "" >>$LOG
			echo "   Error stack removed for brevity. See MarkLogic Logs for full details" >>$LOG
		fi
		#set +o xtrace
	}

	# Usage:
	# executeTestSuite "base_url" "suite_file"
	getTestSuites() {
		curl -s -k \
			--user "$TESTER_USER:$TESTER_PASS" \
			--digest ${TEST_URL}?func=list
	}

	processArgs() {
		# loop over all switches and if --directory is found, set the directory
		# to the next argument
		while [ $# -gt 0 ]; do
			if [ "$1" == "--directory" ]; then
				shift
				cd "$1"
				shift
				echo "Setting directory to $1"
			fi
			if [ "$1" == "--test_port" ]; then
				shift
				PORT_TEST="$1"
				shift
				echo "Setting test port to $PORT_TEST"
			fi
			if [ "$1" == "--after" ]; then
				shift
				AFTER="$1"
				shift
				echo "Setting after to $AFTER"
			fi
		done
	}
	ii() { echo "II $(date) $1"; }
}

##############################################
MLU_LIMIT=${MLU_LIMIT:-1000}
AFTER=1
TESTER_USER=${TESTER_USER:-admin}
TESTER_PASS=${TESTER_PASS:-admin}
PROTOCOL=${MLU_PROTOCOL:-http}
MAIN_HOST=${MLU_MAIN_HOST:-localhost}
PORT_TEST=${MLU_PORT_TEST:-8000}
PORT_MLMANAGE=${MLU_PORT_MLMANAGE:-8002}
source scripts/common.sh
LOG=/tmp/run_unit_tests-$(date +%s).log
touch $LOG
BASE_URL=
TEST_URL=
STOP_ON_FAIL=/tmp/stop_on_fail
test -f "$STOP_ON_FAIL" && rm -f "$STOP_ON_FAIL"

main $URL "$@"
