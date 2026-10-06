#!/bin/bash
# Expanded Maven resolution-strategy diversity experiment: 18 projects sourced
# from Reproducible Central, same 4-combo design validated in the first
# experiment (collector df/bf x version-selector nearest/highest, Maven 4 only
# -- the visiting-order flag was dropped after being shown to have zero
# effect, and Maven 3.9.x was dropped since only the collector flag exists
# there at all).
#
# Requires Maven 4.0.0-rc-5+ and JDK 17+ -- see README.md for setup via
# MVN4_HOME / JAVA17_HOME. Standardizes the build command across all projects
# rather than replaying each project's own release-signing profile from its
# .buildspec (those often invoke -Papache-release / -Peclipse-release etc.,
# which pull in release infra unrelated to what we're measuring).

set -u

# Never let git prompt interactively for credentials on a private/inaccessible
# repo -- fail fast instead. At hundreds-of-projects scale this is a realistic
# occurrence, and an interactive prompt reading stdin is exactly what caused
# the "578 candidates but only ~289 Processing/Skipping log lines" bug: it
# silently stole lines meant for this script's own CSV-reading loop.
export GIT_TERMINAL_PROMPT=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Maven and JDK installs are NOT vendored in this repo (they're large,
# publicly downloadable binaries). Point these env vars at your own local
# installs before running -- see README.md / SETUP for exact versions and
# download links. MVN4_HOME and JAVA17_HOME are required (Maven 4 itself
# needs a JDK >=17 to run); JAVA8_HOME/JAVA11_HOME are optional and only
# affect the two projects with a known older-bytecode-target override below
# (jackson-annotations, mybatis) -- without them, those two builds may fail
# on a bytecode-target mismatch while every other project is unaffected.
MVN4="${MVN4_HOME:?Set MVN4_HOME to the mvn binary of a Maven 4.0.0-rc-5+ install, e.g. /path/to/apache-maven-4.x/bin/mvn -- see README.md}"
if ! "$MVN4" -v 2>/dev/null | grep -q "Apache Maven 4"; then
    echo "ERROR: MVN4_HOME ('$MVN4') did not report as Maven 4.x. This experiment requires Maven 4 (Resolver 2.x) -- see README.md." >&2
    exit 1
fi
NORMALIZE_HASH="python3 $SCRIPT_DIR/normalize-jar-hash.py"
JAVA8="${JAVA8_HOME:-}"
JAVA11="${JAVA11_HOME:-}"
JAVA17="${JAVA17_HOME:?Set JAVA17_HOME to a JDK >=17 install -- required to run Maven 4 itself, see README.md}"
JAVA21="${JAVA21_HOME:-$JAVA17}"
JAVA25="${JAVA25_HOME:-$JAVA17}"

# Per-project overrides discovered while validating each build. Default is
# JDK17 regardless of the buildspec's declared jdk= (most projects tolerate a
# newer host JDK than their target bytecode level; only override when a build
# actually fails on a JDK-version enforcer or an old bytecode target javac no
# longer accepts, matching what happened with mybatis-3/graphhopper in the
# first experiment).
project_subdir() {
    case "$1" in
        *) echo "" ;;
    esac
}
# Maven 4 itself requires JDK17+ to run, regardless of what JDK a project
# needs for its own compilation -- so JAVA_HOME always stays >=17. For
# projects targeting older bytecode than the running JDK's javac still
# accepts (e.g. source/target 6, dropped by javac around JDK 12+), fork the
# compiler plugin to an older javac executable instead.
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

# Default project list is the small 18-project curated set (fast first run);
# pass PROJECT_LIST_FILE=../data/selected-projects.csv for the full 578-
# candidate run this study's headline numbers are based on. Results/logs/
# workspace default to ../output/ (gitignored) so a re-run never overwrites
# the canonical, committed data/ snapshot from the original run.
PROJECT_LIST="${PROJECT_LIST_FILE:-$SCRIPT_DIR/../data/final-selected-projects.csv}"
RESULTS="${RESULTS_FILE:-$SCRIPT_DIR/../output/results-expanded.csv}"
LOG_DIR="$SCRIPT_DIR/../output/logs"
WORKSPACE="$SCRIPT_DIR/../output/build_workspace"
mkdir -p "$(dirname "$RESULTS")"
BUILD_TIMEOUT="${BUILD_TIMEOUT:-3600}"

mkdir -p "$WORKSPACE" "$LOG_DIR"

if [ ! -f "$RESULTS" ]; then
  echo "Project,GroupId,Collector,Selector,TreeHash,JARHash,JARHash_Normalized,BuildTime_sec,ExitCode,Notes" > "$RESULTS"
fi

collectors=("df" "bf")
selectors=("nearest" "highest")

clean_tree() {
    local file="$1"
    sed -i '/Downloading/d' "$file" 2>/dev/null
    sed -i '/Downloaded from/d' "$file" 2>/dev/null
    sed -i '/Progress/d' "$file" 2>/dev/null
    sed -i '/\[INFO\] Scanning/d' "$file" 2>/dev/null
    sed -i '/\[INFO\] Building/d' "$file" 2>/dev/null
    sed -i '/\[INFO\] ----*/d' "$file" 2>/dev/null
    sed -i '/\[INFO\] Total time/d' "$file" 2>/dev/null
    sed -i '/\[INFO\] Finished at/d' "$file" 2>/dev/null
}

run_one_build() {
    local proj_name="$1" group_id="$2" collector="$3" selector="$4"

    export JAVA_HOME
    JAVA_HOME="$(project_java_home "$proj_name")"

    local flags="-Daether.dependencyCollector.impl=$collector -Daether.conflictResolver.versionSelector.selectionStrategy=$selector -Dproject.build.outputTimestamp=2024-01-01T00:00:00Z $(project_extra_flags "$proj_name")"

    local label="${collector}_${selector}"
    local log_file="$LOG_DIR/${proj_name}_${label}.log"

    echo "  [$proj_name] $label"

    local start end build_time exit_code
    start=$(date +%s)
    timeout "$BUILD_TIMEOUT" "$MVN4" clean package $flags -DskipTests -Dmaven.javadoc.skip -Dgpg.skip -Dinvoker.skip < /dev/null > "$log_file" 2>&1
    exit_code=$?
    end=$(date +%s)
    build_time=$((end - start))

    if [ $exit_code -ne 0 ]; then
        echo "$proj_name,$group_id,$collector,$selector,BUILD_FAIL,BUILD_FAIL,BUILD_FAIL,$build_time,$exit_code,BUILD_FAIL" >> "$RESULTS"
        return
    fi

    # write outside the project working directory: some ASF projects (commons-io,
    # commons-compress, commons-csv, maven-checkstyle-plugin) run apache-rat-plugin
    # on the next build and fail on any stray unlicensed file left in the tree --
    # which a tree.txt written into the project dir would be, since `mvn clean`
    # doesn't remove it.
    local tree_file="$LOG_DIR/${proj_name}_${label}_tree.txt"
    "$MVN4" dependency:tree $flags < /dev/null > "$tree_file" 2>&1
    clean_tree "$tree_file"
    local tree_hash jar_hash jar_hash_norm jar_list
    tree_hash=$(sha256sum "$tree_file" 2>/dev/null | awk '{print $1}')
    [ -z "$tree_hash" ] && tree_hash="NO_TREE"

    # exclude target/test-classes and target/classes: some projects (e.g.
    # commons-compress) bundle test-fixture jars there -- including
    # intentionally malformed ones for edge-case tests -- which are build
    # INPUTS copied into target/, not build OUTPUTS, and can crash a zip parser.
    jar_list=$(find . -path "*/target/*.jar" ! -path "*/target/test-classes/*" ! -path "*/target/classes/*" ! -name "*-sources.jar" ! -name "*-javadoc.jar" 2>/dev/null | sort)
    if [ -n "$jar_list" ]; then
        jar_hash=$(echo "$jar_list" | xargs sha256sum 2>/dev/null | awk '{print $1}' | sha256sum | awk '{print $1}')
        # content-based hash: excludes META-INF/DEPENDENCIES and META-INF/maven/**
        # (self-describing dependency-resolution manifests) and hashes decompressed
        # entry content rather than raw zip bytes (sidesteps the module-info.class
        # timestamp gap outputTimestamp doesn't reach). See Part 3 of the report.
        # NOTE: pipe into stdin mode ("-"), never `xargs $NORMALIZE_HASH` --
        # xargs silently splits long argument lists into multiple invocations
        # (seen in practice on large multi-module reactors), and each
        # invocation prints its own hash line, corrupting this field with an
        # embedded newline. Stdin mode guarantees exactly one invocation.
        jar_hash_norm=$(echo "$jar_list" | $NORMALIZE_HASH - 2>/dev/null)
        [ -z "$jar_hash_norm" ] && jar_hash_norm="NO_JAR"
    else
        jar_hash="NO_JAR"
        jar_hash_norm="NO_JAR"
    fi

    echo "$proj_name,$group_id,$collector,$selector,$tree_hash,$jar_hash,$jar_hash_norm,$build_time,$exit_code,SUCCESS" >> "$RESULTS"
}

cd "$WORKSPACE"

# CSV columns: groupId,artifactId,version,gitRepo,gitTag,jdk,tool,command
#
# Read via fd 3, not a pipe into the loop body: piping ("cmd | while read")
# shares stdin between the read loop and anything inside the loop that might
# also read stdin (e.g. git prompting for credentials on an inaccessible
# repo). That silently steals CSV lines meant for `read`, causing rows to be
# skipped with no log trace -- confirmed at scale: a 578-project run only
# logged 289 Processing/Skipping lines. Reading from a dedicated fd leaves
# stdin (fd 0) free for the loop body without racing the outer read.
while IFS=',' read -r groupId artifactId version gitRepo gitTag jdk tool command <&3; do
  gitRepo=$(echo "$gitRepo" | tr -d '\r"')
  gitTag=$(echo "$gitTag" | tr -d '\r"')
  proj_name="$artifactId"

  # Some buildspecs (observed: all io7m.com projects) embed a literal shell
  # command substitution in gitRepo instead of a static URL, e.g.
  # https://github.com/io7m/$(echo "com.io7m.abstand" | sed s/com.io7m.//).git
  # -- Reproducible Central's own tooling evaluates this; a naive parser
  # doesn't, and git clone fails on the literal unevaluated string. Safe to
  # eval here: this data originates from Reproducible Central's own buildspec
  # files, not attacker-controlled input.
  if [[ "$gitRepo" == *'$('* ]]; then
    gitRepo="$(eval echo "$gitRepo" 2>/dev/null)"
  fi

  # resumability: skip a project already fully processed (4 result rows) in a
  # prior (possibly interrupted) run of this script against the same RESULTS file
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
      echo "$proj_name,$groupId,CLONE_FAIL,CLONE_FAIL,CLONE_FAIL,CLONE_FAIL,CLONE_FAIL,0,1,CLONE_FAIL" >> "$RESULTS"
    done
    continue
  fi

  subdir="$(project_subdir "$proj_name")"
  cd "$proj_name/${subdir:-.}"

  if [ ! -f "pom.xml" ]; then
    for i in 1 2 3 4; do
      echo "$proj_name,$groupId,NO_POM,NO_POM,NO_POM,NO_POM,NO_POM,0,1,NO_POM" >> "$RESULTS"
    done
    cd "$WORKSPACE"
    rm -rf "$proj_name"
    continue
  fi

  for collector in "${collectors[@]}"; do
    for selector in "${selectors[@]}"; do
      run_one_build "$proj_name" "$groupId" "$collector" "$selector"
    done
  done

  cd "$WORKSPACE"
  # reclaim disk space at this scale (hundreds of projects): the source clone
  # and build output aren't needed once this project's 4 configs are recorded.
  rm -rf "$proj_name"
done 3< <(tail -n +2 "$PROJECT_LIST")

echo "Expanded experiment completed. Results saved in $RESULTS"
