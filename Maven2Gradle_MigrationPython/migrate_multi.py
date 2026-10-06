#!/usr/bin/env python3
import re, sys
import xml.etree.ElementTree as ET
from pathlib import Path

# Convert Maven property names to valid Kotlin identifiers
def to_kotlin_val(name):
    parts = re.split(r'[\.-]+', name)
    return parts[0] + ''.join(p.capitalize() for p in parts[1:])

# Map Maven scopes to Gradle configurations
def scope_map(scope, optional):
    if scope == 'compile': return 'compileOnly' if optional else 'implementation'
    if scope == 'provided': return 'compileOnly'
    if scope == 'runtime':  return 'runtimeOnly'
    if scope == 'test':     return 'testImplementation'
    return 'implementation'

# Parse a POM into a structured dict including modules
# Safely handles missing text in properties and profiles
def parse_pom(path):
    ns = {'m': 'http://maven.apache.org/POM/4.0.0'}
    tree = ET.parse(path)
    root = tree.getroot()

    # Modules list
    modules = [m.text.strip() for m in root.findall('m:modules/m:module', ns) if m.text]

    # Properties
    props = {}
    for p in root.findall('m:properties/*', ns):
        key = p.tag.replace(f"{{{ns['m']}}}", '')
        props[key] = p.text.strip() if p.text else ''

    # Profile overrides
    profiles = {}
    for prof in root.findall('m:profiles/m:profile', ns):
        pid = prof.findtext('m:id', namespaces=ns) or ''
        prof_props = {}
        for q in prof.findall('m:properties/*', ns):
            key = q.tag.replace(f"{{{ns['m']}}}", '')
            prof_props[key] = q.text.strip() if q.text else ''
        if pid:
            profiles[pid] = prof_props

    # Dependencies
    deps = []
    for d in root.findall('m:dependencies/m:dependency', ns):
        deps.append({
            'group': d.findtext('m:groupId', namespaces=ns) or '',
            'artifact': d.findtext('m:artifactId', namespaces=ns) or '',
            'version': d.findtext('m:version', namespaces=ns) or '',
            'scope': d.findtext('m:scope', default='compile', namespaces=ns) or 'compile',
            'optional': d.findtext('m:optional', default='false', namespaces=ns) == 'true'
        })

    # Plugins
    plugins = [p.findtext('m:artifactId', namespaces=ns) or '' for p in root.findall('m:build/m:plugins/m:plugin', ns)]

    # Project metadata + description
    metadata = {
        'group': root.findtext('m:groupId', namespaces=ns) or root.findtext('m:parent/m:groupId', namespaces=ns) or '',
        'version': root.findtext('m:version', namespaces=ns) or root.findtext('m:parent/m:version', namespaces=ns) or '',
        'description': root.findtext('m:description', default='', namespaces=ns) or ''
    }

    return {
        'modules': modules,
        'properties': props,
        'profiles': profiles,
        'dependencies': deps,
        'plugins': plugins,
        'metadata': metadata
    }

# Generate settings.gradle.kts
def generate_settings(name, modules):
    include_list = ', '.join(f'"{m}"' for m in modules)
    return f"rootProject.name = \"{name}\"\ninclude({include_list})"

# Generate gradle.properties content
def generate_properties(meta, props):
    lines = [f"group={meta['group']}", f"version={meta['version']}"]
    for k, v in props.items():
        lines.append(f"{k}={v}")
    return '\n'.join(lines)

# Generate root build.gradle.kts shared config
def generate_root_build(data):
    props = data['properties']
    plugins = data['plugins']
    meta = data['metadata']
    lines = []
    # Plugins
    lines.append('plugins {')
    lines.append('    java')
    lines.append('    jacoco')
    if 'maven-checkstyle-plugin' in plugins:
        lines.append('    checkstyle')
    lines.append('}')
    lines.append('')
    # Group, version, description
    lines.append(f'group = "{meta["group"]}"')
    lines.append(f'version = "{meta["version"]}"')
    if meta.get('description'):
        desc = meta['description'].replace('"','\\"')
        lines.append(f'description = "{desc}"')
    lines.append('')
    # Java toolchain
    lines.append('java {')
    lines.append('    toolchain.languageVersion.set(JavaLanguageVersion.of(17))')
    lines.append('    withJavadocJar()')
    lines.append('    withSourcesJar()')
    lines.append('}')
    lines.append('')
    # Version vals
    for k, v in props.items():
        var = to_kotlin_val(k)
        lines.append(f'val {var} = "{v}"')
    lines.append('')
    # Repositories
    lines.append('repositories {')
    lines.append('    mavenCentral()')
    lines.append('}')
    lines.append('')
    # Subprojects
    lines.append('subprojects {')
    lines.append('    apply(plugin = "java")')
    lines.append('    apply(plugin = "jacoco")')
    if 'maven-checkstyle-plugin' in plugins:
        lines.append('    apply(plugin = "checkstyle")')
    lines.append('')
    lines.append('    java {')
    lines.append('        toolchain.languageVersion.set(JavaLanguageVersion.of(11))')
    lines.append('    }')
    lines.append('')
    lines.append('    repositories {')
    lines.append('        mavenCentral()')
    lines.append('    }')
    lines.append('')
    lines.append('    tasks.withType<Jar> {')
    lines.append('        manifest {')
    lines.append('            attributes(')
    lines.append('                "Implementation-Title" to project.name,')
    lines.append('                "Implementation-Version" to project.version,')
    lines.append('                "Multi-Release" to "true"')
    lines.append('            )')
    lines.append('        }')
    lines.append('    }')
    lines.append('')
    lines.append('    checkstyle {')
    lines.append('        configFile = file("${rootProject.projectDir}/pdfbox-checkstyle-5.xml")')
    lines.append('        isIgnoreFailures = false')
    lines.append('    }')
    lines.append('')
    lines.append('    tasks.withType<Test> {')
    lines.append('        useJUnitPlatform()')
    lines.append('    }')
    lines.append('}')
    lines.append('')
    # Release ZIP
    lines.append('tasks.register<Zip>("apacheRelease") {')
    lines.append('    group = "distribution"')
    lines.append('    archiveBaseName.set("pdfbox-${project.version}")')
    lines.append('    destinationDirectory.set(file("$buildDir/release"))')
    lines.append('    from("RELEASE-NOTES.txt")')
    lines.append('    subprojects.forEach {')
    lines.append('        from(it.buildDir.resolve("libs")) {')
    lines.append('            include("*.jar")')
    lines.append('        }')
    lines.append('    }')
    lines.append('}')
    return '\n'.join(lines)

# Generate module build.gradle.kts minimal
def generate_module_build(data):
    lines = ['dependencies {']
    for dep in data.get('dependencies', []):
        cfg = scope_map(dep['scope'], dep['optional'])
        ver = f":{dep['version']}" if dep['version'] else ''
        lines.append(f'    {cfg}("{dep["group"]}:{dep["artifact"]}{ver}")')
    lines.append('}')
    return '\n'.join(lines)

# Main
def main():
    if len(sys.argv) != 2:
        print('Usage: migrate_multi.py <root-project-dir>')
        sys.exit(1)

    root = Path(sys.argv[1]).resolve()
    out = root / 'gradle-converted'
    out.mkdir(exist_ok=True)

    data = parse_pom(root / 'pom.xml')

    # settings.gradle.kts
    (out / 'settings.gradle.kts').write_text(generate_settings(root.name, data['modules']), encoding='utf-8')
    print('settings.gradle.kts generated')

    # gradle.properties
    (out / 'gradle.properties').write_text(generate_properties(data['metadata'], data['properties']), encoding='utf-8')
    print('gradle.properties generated')

    # root build.gradle.kts
    (out / 'build.gradle.kts').write_text(generate_root_build(data), encoding='utf-8')
    print('root build.gradle.kts generated')

    # modules
    for m in data['modules']:
        mod_dir = out / m
        mod_dir.mkdir(exist_ok=True)
        mod_data = parse_pom(root / m / 'pom.xml')
        (mod_dir / 'build.gradle.kts').write_text(generate_module_build(mod_data), encoding='utf-8')
        print(f' module {m}/build.gradle.kts generated')

if __name__ == '__main__':
    main()
