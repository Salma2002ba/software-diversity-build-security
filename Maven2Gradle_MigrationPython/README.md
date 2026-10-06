# Maven → Gradle migration in Python

Two scripts that read a `pom.xml` and generate the Gradle equivalent in Kotlin DSL. They produce
the **second build path** of the study: the same code, built by Gradle instead of Maven.

| Script | For which project | What it generates |
|---|---|---|
| `migrate_pom_to_gradle.py` | Single-module project | `build.gradle.kts` |
| `migrate_multi.py` | Multi-module project | `settings.gradle.kts`, `gradle.properties`, the root `build.gradle.kts` and one per module |

Both only use the Python standard library.

## Usage

```bash
# Single-module project
python3 migrate_pom_to_gradle.py helloxrd/pom.xml helloxrd/build.gradle.kts

# Multi-module project: the root folder containing the parent pom.xml
python3 migrate_multi.py path/to/project
```

## What gets converted

- **Dependencies**, with scope mapping:

  | Maven scope | Gradle configuration |
  |---|---|
  | `compile` | `implementation` (`compileOnly` if `optional`) |
  | `provided` | `compileOnly` |
  | `runtime` | `runtimeOnly` |
  | `test` | `testImplementation` |

- **Properties** from the `pom.xml`, renamed to valid Kotlin identifiers (`log4j.version` becomes
  `log4jVersion`).
- **Profiles** that override properties.
- **Java version** (`sourceCompatibility`, `targetCompatibility`).

## Sample project: `helloxrd`

A small Java project with its `pom.xml` and the matching `build.gradle.kts`, used as a test bed for
the migration. The repository's pipeline reruns the migration on this `pom.xml` on every push.

## Limitations

- `migrate_pom_to_gradle.py` was written for MyBatis: it reads specific properties from its
  `pom.xml` (Byte Buddy, Derby, Log4j, Mockito versions…). On another project, these values stay
  empty.
- Not every Maven **plugin** has a direct equivalent: their configuration is ported by hand, which
  is the "reproducing plugins and profiles" step of the study.
- The conversion aims for a **functionally** equivalent build, not a byte-for-byte identical
  artifact. That gap is exactly what [`M2G/`](../M2G/) measures.
