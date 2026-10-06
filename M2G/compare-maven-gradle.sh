#!/usr/bin/env bash
#
# Compares two JARs of the same project, one built with Maven and one with Gradle:
# functional test, MANIFEST.MF, file listing, recursive diff and Syft SBOM.
#
# Usage: bash compare-maven-gradle.sh [maven-jar] [gradle-jar]

set -euo pipefail

# defaults
JAR_MAVEN=${1:-mybatis-maven.jar}
JAR_GRADLE=${2:-mybatis-gradle.jar}

# Existence
for f in "$JAR_MAVEN" "$JAR_GRADLE"; do
  [[ -f $f ]] || { echo "File not found: $f"; exit 1; }
done

echo "=== Comparaison Maven vs Gradle ==="
echo "Maven JAR : $JAR_MAVEN"
echo "Gradle JAR: $JAR_GRADLE"
echo

# --- Step 1 – Functional? ---
echo ">>> Step 1 – Functional test"
javac -cp .:mybatis-maven.jar TestMyBatis.java
javac -cp .:mybatis-gradle.jar TestMyBatis.java
java -cp .:mybatis-maven.jar TestMyBatis
java -cp .:mybatis-gradle.jar TestMyBatis
echo

# --- Step 2 – MANIFEST.MF ---
echo ">>> Step 2 – MANIFEST.MF"
unzip -p "$JAR_MAVEN" META-INF/MANIFEST.MF > manifest-maven.txt
unzip -p "$JAR_GRADLE" META-INF/MANIFEST.MF > manifest-gradle.txt
echo "Diff du MANIFEST"
diff -u manifest-maven.txt manifest-gradle.txt || true
echo

# --- Step 3 – JAR listing ---
echo ">>> Step 3 – JAR listing"
jar tf "$JAR_MAVEN" > contents-maven.txt
jar tf "$JAR_GRADLE" > contents-gradle.txt
echo "Diff of the file listings"
diff -u contents-maven.txt contents-gradle.txt || true
echo

# --- Step 4 – Extraction & recursive diff ---
echo ">>> Step 4 – Extraction and diff -r"
rm -rf maven-extracted gradle-extracted
mkdir maven-extracted gradle-extracted
( cd maven-extracted && jar xf "../$JAR_MAVEN" )
( cd gradle-extracted && jar xf "../$JAR_GRADLE" )
diff -r maven-extracted gradle-extracted > full-structure-diff.txt || true
echo "Result in full-structure-diff.txt"
echo


# --- Step 5 – SBOM (Syft) ---
echo ">>> Step 5 – SBOM generation"
syft "$JAR_MAVEN"  -o json > sbom-maven.json
syft "$JAR_GRADLE" -o json > sbom-gradle.json
echo "Diff SBOM JSON"
diff -u sbom-maven.json sbom-gradle.json || true
echo



echo "=== End of the comparison pipeline ==="

