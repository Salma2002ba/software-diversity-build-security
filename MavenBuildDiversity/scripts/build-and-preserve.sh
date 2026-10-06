#!/bin/bash
# For one project (arg $1 = artifactId as it appears in final-selected-projects.csv),
# build df+nearest and df+highest, preserving each combo's jars and dependency tree
# in diffoscope-work/<project>/<selector>/ before the next `mvn clean` wipes them.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# See README.md for setup -- both env vars are required.
MVN4="${MVN4_HOME:?Set MVN4_HOME to the mvn binary of a Maven 4.0.0-rc-5+ install -- see README.md}"
JAVA17="${JAVA17_HOME:?Set JAVA17_HOME to a JDK >=17 install -- see README.md}"
WORKSPACE="$SCRIPT_DIR/../output/build_workspace"
OUT_DIR="$SCRIPT_DIR/../output/diffoscope-work"
TARGET_PROJECT="$1"

export JAVA_HOME="$JAVA17"

mkdir -p "$OUT_DIR"

proj_line=$(grep ",$TARGET_PROJECT," "$SCRIPT_DIR/../data/final-selected-projects.csv" | head -1)
if [ -z "$proj_line" ]; then
    # artifactId is first-ish field for some; try matching second CSV field directly
    proj_line=$(awk -F',' -v p="$TARGET_PROJECT" '$2==p' "$SCRIPT_DIR/../data/final-selected-projects.csv")
fi
if [ -z "$proj_line" ]; then
    echo "Project $TARGET_PROJECT not found in final-selected-projects.csv"
    exit 1
fi

echo "=== $TARGET_PROJECT ==="
cd "$WORKSPACE/$TARGET_PROJECT" || { echo "workspace dir missing, expected prior clone"; exit 1; }

for selector in nearest highest; do
    echo "  building df/$selector ..."
    flags="-Daether.dependencyCollector.impl=df -Daether.conflictResolver.versionSelector.selectionStrategy=$selector -Dproject.build.outputTimestamp=2024-01-01T00:00:00Z"
    "$MVN4" clean package $flags -DskipTests -Dmaven.javadoc.skip -Dgpg.skip -Dinvoker.skip > "$OUT_DIR/${TARGET_PROJECT}_${selector}_build.log" 2>&1
    exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "  BUILD FAILED for $selector (exit $exit_code) -- see $OUT_DIR/${TARGET_PROJECT}_${selector}_build.log"
        continue
    fi

    dest="$OUT_DIR/$TARGET_PROJECT/$selector"
    mkdir -p "$dest/jars"
    find . -path "*/target/*.jar" ! -name "*-sources.jar" ! -name "*-javadoc.jar" 2>/dev/null | while read -r j; do
        flat=$(echo "$j" | sed 's#^\./##; s#/#__#g')
        cp "$j" "$dest/jars/$flat"
    done

    "$MVN4" dependency:tree $flags > "$dest/tree.txt" 2>&1
    echo "  done: $(ls "$dest/jars" | wc -l) jar(s) preserved"
done
