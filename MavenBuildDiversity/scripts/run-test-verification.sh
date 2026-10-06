#!/bin/bash
# Test-verification pass over the 359 projects that built successfully (clean
# package -DskipTests) under all 4 resolver configurations in the main study.
# Re-runs each project's own test suite (clean test, tests NOT skipped) under
# the same 4 configs to confirm they actually pass, and to check whether test
# outcomes ever differ by resolver strategy. Adapted from run-experiment.sh --
# same JDK selection, gitRepo eval fix, and resumability logic (all already
# hardened at 578-project scale), with -DskipTests removed and a surefire
# summary parser added in its place.

set -u

export GIT_TERMINAL_PROMPT=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# See README.md / SETUP for exact versions and download links. MVN4_HOME and
# JAVA17_HOME are required; JAVA8_HOME/JAVA11_HOME are optional (only affect
# jackson-annotations / mybatis, see project_extra_flags below).
MVN4="${MVN4_HOME:?Set MVN4_HOME to the mvn binary of a Maven 4.0.0-rc-5+ install, e.g. /path/to/apache-maven-4.x/bin/mvn -- see README.md}"
if ! "$MVN4" -v 2>/dev/null | grep -q "Apache Maven 4"; then
    echo "ERROR: MVN4_HOME ('$MVN4') did not report as Maven 4.x. This experiment requires Maven 4 (Resolver 2.x) -- see README.md." >&2
    exit 1
fi
PARSE_TESTS="python3 $SCRIPT_DIR/parse-test-summary.py"
JAVA8="${JAVA8_HOME:-}"
JAVA11="${JAVA11_HOME:-}"
JAVA17="${JAVA17_HOME:?Set JAVA17_HOME to a JDK >=17 install -- required to run Maven 4 itself, see README.md}"
JAVA21="${JAVA21_HOME:-$JAVA17}"
JAVA25="${JAVA25_HOME:-$JAVA17}"

project_java_home() {
    case "$1" in
        *) echo "$JAVA17" ;;
    esac
}
project_extra_flags() {
    case "$1" in
        jackson-annotations)
            [ -n "$JAVA8" ] && echo "-Dmaven.compiler.fork=true -Dmaven.compiler.executable=$JAVA8/bin/javac" ;;
        mybatis)
            [ -n "$JAVA11" ] && echo "-Dmaven.compiler.fork=true -Dmaven.compiler.executable=$JAVA11/bin/javac" ;;
        *) echo "" ;;
    esac
}

# Defaults to ../output/ (gitignored) so a re-run never overwrites the
# canonical, committed data/test-verify-results.csv from the original run.
PROJECT_LIST="${PROJECT_LIST_FILE:-$SCRIPT_DIR/../data/test-verify-projects.csv}"
RESULTS="${RESULTS_FILE:-$SCRIPT_DIR/../output/test-verify-results.csv}"
LOG_DIR="$SCRIPT_DIR/../output/test-logs"
WORKSPACE="$SCRIPT_DIR/../output/test_build_workspace"
mkdir -p "$(dirname "$RESULTS")"
BUILD_TIMEOUT="${BUILD_TIMEOUT:-3600}"

mkdir -p "$WORKSPACE" "$LOG_DIR"

if [ ! -f "$RESULTS" ]; then
  echo "Project,GroupId,Collector,Selector,TestsRun,Failures,Errors,Skipped,BuildTime_sec,ExitCode,Status" > "$RESULTS"
fi

collectors=("df" "bf")
selectors=("nearest" "highest")

run_one_test() {
    local proj_name="$1" group_id="$2" collector="$3" selector="$4"

    export JAVA_HOME
    JAVA_HOME="$(project_java_home "$proj_name")"

    local flags="-Daether.dependencyCollector.impl=$collector -Daether.conflictResolver.versionSelector.selectionStrategy=$selector -Dproject.build.outputTimestamp=2024-01-01T00:00:00Z $(project_extra_flags "$proj_name")"

    local label="${collector}_${selector}"
    local log_file="$LOG_DIR/${proj_name}_${label}.log"

    echo "  [$proj_name] $label"

    local start end build_time exit_code
    start=$(date +%s)
    timeout "$BUILD_TIMEOUT" "$MVN4" clean test $flags -Dmaven.javadoc.skip -Dgpg.skip -Dinvoker.skip < /dev/null > "$log_file" 2>&1
    exit_code=$?
    end=$(date +%s)
    build_time=$((end - start))

    local counts tests_run failures errors skipped
    counts=$($PARSE_TESTS "$log_file")
    tests_run=$(echo "$counts" | cut -d',' -f1)
    failures=$(echo "$counts" | cut -d',' -f2)
    errors=$(echo "$counts" | cut -d',' -f3)
    skipped=$(echo "$counts" | cut -d',' -f4)

    local status
    if [ "$exit_code" -eq 0 ]; then
        status="PASS"
    elif [ "$((failures + errors))" -gt 0 ]; then
        status="TEST_FAILURES"
    else
        status="BUILD_FAIL"
    fi

    echo "$proj_name,$group_id,$collector,$selector,$tests_run,$failures,$errors,$skipped,$build_time,$exit_code,$status" >> "$RESULTS"
}

cd "$WORKSPACE"

while IFS=',' read -r groupId artifactId version gitRepo gitTag jdk tool command <&3; do
  gitRepo=$(echo "$gitRepo" | tr -d '\r"')
  gitTag=$(echo "$gitTag" | tr -d '\r"')
  proj_name="$artifactId"

  if [[ "$gitRepo" == *'$('* ]]; then
    gitRepo="$(eval echo "$gitRepo" 2>/dev/null)"
  fi

  existing_rows=$(awk -F',' -v p="$proj_name" '$1==p' "$RESULTS" 2>/dev/null | wc -l)
  if [ "$existing_rows" -ge 4 ]; then
    echo "=== Skipping $proj_name (already has $existing_rows result rows) ==="
    continue
  fi

  echo "=== Processing $proj_name ($groupId : $version, tag=$gitTag) ==="

  if [ ! -d "$proj_name" ]; then
    git clone --depth 1 --branch "$gitTag" "$gitRepo" "$proj_name" < /dev/null 2>&1 | tail -5
    if [ ! -d "$proj_name" ]; then
      echo "  shallow clone-by-tag failed, retrying with full clone + checkout"
      git clone "$gitRepo" "$proj_name" < /dev/null 2>&1 | tail -5
      if [ -d "$proj_name" ]; then
        (cd "$proj_name" && git checkout "$gitTag" < /dev/null 2>&1 | tail -5)
      fi
    fi
  fi

  if [ ! -d "$proj_name" ]; then
    for i in 1 2 3 4; do
      echo "$proj_name,$groupId,CLONE_FAIL,CLONE_FAIL,0,0,0,0,0,1,CLONE_FAIL" >> "$RESULTS"
    done
    continue
  fi

  cd "$proj_name"

  if [ ! -f "pom.xml" ]; then
    for i in 1 2 3 4; do
      echo "$proj_name,$groupId,NO_POM,NO_POM,0,0,0,0,0,1,NO_POM" >> "$RESULTS"
    done
    cd "$WORKSPACE"
    rm -rf "$proj_name"
    continue
  fi

  for collector in "${collectors[@]}"; do
    for selector in "${selectors[@]}"; do
      run_one_test "$proj_name" "$groupId" "$collector" "$selector"
    done
  done

  cd "$WORKSPACE"
  rm -rf "$proj_name"
done 3< <(tail -n +2 "$PROJECT_LIST")

echo "Test-verification pass completed. Results saved in $RESULTS"
