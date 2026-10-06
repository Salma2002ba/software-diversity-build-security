#!/bin/bash
# Parses every .buildspec in reproducible-central/content into a flat CSV,
# cross-referencing the matching .buildcompare file (same dir, named
# "${artifactId}-${version}.buildcompare") to record reproducibility status.
set -u

RC_DIR="${1:-reproducible-central}"
OUT="all-maven-projects.csv"

echo "groupId,artifactId,version,gitRepo,gitTag,jdk,tool,command,ko,ok,reproducible" > "$OUT"

count=0
find "$RC_DIR/content" -iname "*.buildspec" | while read -r spec; do
    dir=$(dirname "$spec")

    groupId=""; artifactId=""; version=""; gitRepo=""; gitTag=""; jdk=""; tool=""; command=""

    while IFS='=' read -r key value; do
        key="${key%$'\r'}"; value="${value%$'\r'}"
        # strip comments/blank lines
        case "$key" in
            ""|\#*) continue ;;
        esac
        value="${value%\"}"; value="${value#\"}"
        case "$key" in
            groupId) groupId="$value" ;;
            artifactId) artifactId="$value" ;;
            version) version="$value" ;;
            gitRepo) gitRepo="$value" ;;
            gitTag) gitTag="$value" ;;
            jdk) jdk="$value" ;;
            tool) tool="$value" ;;
            command) command="$value" ;;
        esac
    done < "$spec"

    [ -z "$artifactId" ] && continue
    [ -z "$version" ] && continue

    # resolve ${version} / ${groupId} / ${artifactId} substitutions in gitTag and gitRepo
    gitTag="${gitTag//\$\{version\}/$version}"
    gitTag="${gitTag//\$\{groupId\}/$groupId}"
    gitTag="${gitTag//\$\{artifactId\}/$artifactId}"
    gitRepo="${gitRepo//\$\{version\}/$version}"
    gitRepo="${gitRepo//\$\{groupId\}/$groupId}"
    gitRepo="${gitRepo//\$\{artifactId\}/$artifactId}"

    buildcompare="$dir/${artifactId}-${version}.buildcompare"
    ko=""; ok=""; reproducible="unknown"
    if [ -f "$buildcompare" ]; then
        ko=$(grep -m1 "^ko=" "$buildcompare" | cut -d= -f2)
        ok=$(grep -m1 "^ok=" "$buildcompare" | cut -d= -f2)
        if [ "$ko" = "0" ] && [ -n "$ok" ] && [ "$ok" -gt 0 ] 2>/dev/null; then
            reproducible="true"
        else
            reproducible="false"
        fi
    fi

    # CSV-escape fields that may contain commas/quotes (command, gitRepo)
    esc_command=$(printf '%s' "$command" | sed 's/"/""/g')
    esc_gitRepo=$(printf '%s' "$gitRepo" | sed 's/"/""/g')

    echo "$groupId,$artifactId,$version,\"$esc_gitRepo\",$gitTag,$jdk,$tool,\"$esc_command\",$ko,$ok,$reproducible" >> "$OUT"

    count=$((count + 1))
    if [ $((count % 500)) -eq 0 ]; then
        echo "  processed $count buildspecs..." >&2
    fi
done

echo "Done. Wrote $OUT" >&2
wc -l "$OUT"
