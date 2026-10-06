#!/usr/bin/env bash
set -euo pipefail

# Working files
MAVEN_OUT=deps-maven.txt
GRADLE_OUT=deps-gradle.txt
MAVEN_HIER=deps-maven-hierarchy.txt
GRADLE_HIER=deps-gradle-hierarchy.txt

echo "==[1] Fetching the Maven tree (compile) =="
mvn dependency:tree -Dscope=compile -Dverbose \
  | grep -v "Downloading" > "$MAVEN_OUT"

echo "==[2] Fetching the Gradle tree (compileClasspath) =="
./gradlew dependencies --configuration compileClasspath --quiet \
  | grep -v ">" > "$GRADLE_OUT"

echo "==[3] Analyzing the hierarchies =="

#
# --- Maven analysis ---
#
declare -a direct_mvn
declare -A trans_mvn
current=""

while IFS= read -r line; do
  # 1) direct dependency
  if [[ $line =~ ^\[INFO\]\ ([\+\-\\]+)[[:space:]]*([^:]+):([^:]+):jar:([^:]+): ]]; then
    grp="${BASH_REMATCH[2]}"
    art="${BASH_REMATCH[3]}"
    ver="${BASH_REMATCH[4]}"
    current="$grp:$art:$ver"
    direct_mvn+=( "$current" )

  # 2) regular transitive dependency
  elif [[ $line =~ ^\[INFO\]\ \|[[:space:]]*\\-[[:space:]]*([^:]+):([^:]+):jar:([^:]+): ]]; then
    grp="${BASH_REMATCH[1]}"
    art="${BASH_REMATCH[2]}"
    ver="${BASH_REMATCH[3]}"
    td="$grp:$art:$ver"
    trans_mvn["$current"]+="$td "
  fi
done < "$MAVEN_OUT"

# Write the Maven file
{
  echo "## Maven hierarchy (direct -> transitive)"
  for dep in "${direct_mvn[@]}"; do
    echo "- $dep"
    for td in ${trans_mvn[$dep]:-}; do
      echo "   -> $td"
    done
  done
} > "$MAVEN_HIER"


#
# --- Gradle analysis ---
#
declare -a direct_grd
declare -A trans_grd
current=""

while IFS= read -r line; do
  # direct dependency
  if [[ $line =~ ^[[:space:]]*(\+---|\\---)[[:space:]]*([^:]+:[^:]+:[^:]+) ]]; then
    current="${BASH_REMATCH[2]}"
    direct_grd+=( "$current" )

  # transitive dependency
  elif [[ $line =~ ^[[:space:]]*\|[[:space:]]*\\---[[:space:]]*([^:]+:[^:]+:[^:]+) ]]; then
    trans_grd["$current"]+="${BASH_REMATCH[1]} "
  fi
done < "$GRADLE_OUT"

# Write the Gradle file in **Maven order**, plus any extras
{
  echo "## Gradle hierarchy (direct -> transitive)"
  # first everything Maven listed, in the same order
  for dep in "${direct_mvn[@]}"; do
    if [[ " ${direct_grd[*]} " == *" $dep "* ]] || [[ -n "${trans_grd[$dep]:-}" ]]; then
      echo "- $dep"
      for td in ${trans_grd[$dep]:-}; do
        echo "   -> $td"
      done
    fi
  done
  # then the direct Gradle dependencies Maven did not list
  for dep in "${direct_grd[@]}"; do
    if [[ ! " ${direct_mvn[*]} " == *" $dep "* ]]; then
      echo "- $dep"
      for td in ${trans_grd[$dep]:-}; do
        echo "   -> $td"
      done
    fi
  done
} > "$GRADLE_HIER"

# Quick display
echo
echo "### Maven ###"
cat "$MAVEN_HIER"
echo
echo "### Gradle ###"
cat "$GRADLE_HIER"

echo
echo "Hierarchies exported to:"
echo "  • $MAVEN_HIER"
echo "  • $GRADLE_HIER"
