#!/bin/bash
# Repeatedly build mybatis-spring at df+nearest to establish divergence frequency.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# See README.md for setup -- both env vars are required.
MVN4="${MVN4_HOME:?Set MVN4_HOME to the mvn binary of a Maven 4.0.0-rc-5+ install -- see README.md}"
export JAVA_HOME="${JAVA17_HOME:?Set JAVA17_HOME to a JDK >=17 install -- see README.md}"

mkdir -p "$SCRIPT_DIR/../output/logs"
cd "$SCRIPT_DIR/../output/build_workspace/mybatis-spring"
OUT="$SCRIPT_DIR/../output/mybatis-spring-repeats.csv"
echo "run,tree_hash,jar_hash_norm,build_time" > "$OUT"

N="${1:-12}"
for i in $(seq 1 "$N"); do
    flags="-Daether.dependencyCollector.impl=df -Daether.conflictResolver.versionSelector.selectionStrategy=nearest -Dproject.build.outputTimestamp=2024-01-01T00:00:00Z"
    start=$(date +%s)
    "$MVN4" clean package $flags -DskipTests -Dmaven.javadoc.skip -Dgpg.skip -Dinvoker.skip > "$SCRIPT_DIR/../output/logs/mybatis-spring_repeat_$i.log" 2>&1
    end=$(date +%s)
    "$MVN4" dependency:tree $flags > "$SCRIPT_DIR/../output/logs/mybatis-spring_repeat_${i}_tree.txt" 2>&1
    sed -i '/Downloading/d;/Progress/d;/\[INFO\] Scanning/d;/\[INFO\] Building/d;/\[INFO\] ----*/d;/\[INFO\] Total time/d;/\[INFO\] Finished at/d' "$SCRIPT_DIR/../output/logs/mybatis-spring_repeat_${i}_tree.txt"
    tree_hash=$(sha256sum "$SCRIPT_DIR/../output/logs/mybatis-spring_repeat_${i}_tree.txt" | awk '{print $1}')
    jar_list=$(find . -path "*/target/*.jar" ! -path "*/target/test-classes/*" ! -path "*/target/classes/*" ! -name "*-sources.jar" ! -name "*-javadoc.jar" | sort)
    jar_hash_norm=$(echo "$jar_list" | xargs python3 "$SCRIPT_DIR/normalize-jar-hash.py" 2>/dev/null)
    echo "$i,$tree_hash,$jar_hash_norm,$((end-start))" >> "$OUT"
    echo "run $i: tree=$tree_hash jar_norm=$jar_hash_norm"
done
echo "Done. See $OUT"
