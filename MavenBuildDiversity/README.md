# Maven Build-Pipeline Diversity

A systematic study of how Maven's dependency-collector, version-conflict-selector, and
dependency-graph-visiting resolver strategies affect build reproducibility, dependency-tree
structure, test-suite correctness, and supply-chain attack surface — across a 572-project
real-world corpus sourced from [Reproducible Central](https://github.com/aalmiray/reproducible-central).

## Headline findings

| Aspect | Effect on final output | Effect on tampering detection |
|---|---|---|
| Dependency collector (`df` / `bf`) | None — zero effect on JAR hash | Neutral — no detection value |
| **Version-conflict selector (`nearest` / `highest`)** | **Real — 46% of projects diverge** | **The one dimension with real security value** |
| Graph-visiting strategy (`preOrder`/`postOrder`/`levelOrder`) | None — not even classpath order | No value — never reaches Maven's build lifecycle |
| POM declaration order | Real, in split-package scenarios | A blind spot: not covered by collector × selector diversity |

This covers four supporting experiments: the 572-project resolver-diversity study, a JPMS/
`module-info.class` reproducibility investigation, a dependency-hijack security simulation, and
a 359-project test-correctness verification pass.

## Repository layout

```
scripts/       the experiment harness and analysis code
data/          the actual experimental datasets (CSV)
experiments/   small, self-contained source projects used as test fixtures
output/        (gitignored) where re-running the scripts writes results/logs
```

### `data/`

| File | What it is |
|---|---|
| `selected-projects.csv` | 578 candidates filtered from Reproducible Central |
| `final-selected-projects.csv` | small 18-project curated subset (fast first run) |
| `results-expanded.csv` | the 572-project × 4-config main dataset |
| `test-verify-projects.csv` | the 359 projects that built successfully under all 4 configs |
| `test-verify-results.csv` | test-suite pass/fail for those 359 projects × 4 configs |

### `experiments/`

- `jpms-verify/` — minimal JPMS reproducer used to isolate the `module-info.class` timestamp bug
- `hijack-sim/` — the four hand-authored modules from the dependency-hijack synthetic
  proof-of-concept (`innocuous-lib`, `victim-lib`, `fake-commons-codec`, `consumer`). All
  artifacts are inert marker JARs with no executable payload; each module's `pom.xml` documents
  the threat model and diamond-conflict graph shape inline.

## Setup

You'll need your own local installs of:

- **Maven 4.0.0-rc-5 or later** (the first release line to expose the collector/selector/visitor
  strategies as configuration properties) — [download](https://maven.apache.org/download.cgi)
- **JDK 17+** (required to run Maven 4 itself)
- Optionally, **JDK 8** and **JDK 11** (only needed to build `jackson-annotations` and `mybatis`
  respectively, which target older bytecode — every other project is unaffected if you skip these)
- Python 3
- Git

Point the scripts at your installs via environment variables:

```bash
export MVN4_HOME=/path/to/apache-maven-4.x/bin/mvn
export JAVA17_HOME=/path/to/jdk-17
export JAVA8_HOME=/path/to/jdk-8    # optional
export JAVA11_HOME=/path/to/jdk-11  # optional
```

## Reproducing the experiment

```bash
# Fast first run: 18 curated projects, 4 configs each
bash scripts/run-experiment.sh

# Full run: all 578 candidates (this is what data/results-expanded.csv was built from)
PROJECT_LIST_FILE=data/selected-projects.csv bash scripts/run-experiment.sh

# Analyze results
python3 scripts/analyze-results.py output/results-expanded.csv
python3 scripts/verify-convergence.py output/results-expanded.csv

# Test-correctness verification pass (drops -DskipTests, runs the real test suites)
PROJECT_LIST_FILE=data/test-verify-projects.csv bash scripts/run-test-verification.sh
```

Results, logs, and build workspaces are written to `output/` (gitignored) — re-running never
overwrites the committed `data/` snapshot.

## License

MIT — see [LICENSE](LICENSE).
