#!/usr/bin/env python3
import re, sys
import xml.etree.ElementTree as ET
from pathlib import Path

def parse_pom(pom_path):
    ns = {'m': 'http://maven.apache.org/POM/4.0.0'}
    tree = ET.parse(pom_path)
    root = tree.getroot()

    # Extract the first license comment
    raw = Path(pom_path).read_text(encoding='utf-8')
    lic_match = re.search(r'<!--(.*?)-->', raw, re.S)
    license_block = lic_match.group(1).strip() if lic_match else ''

    def txt(path):
        e = root.find(path, ns)
        return e.text.strip() if e is not None and e.text else ''

    data = {
        'license': license_block,
        'properties': {},
        'profiles': {},
        'dependencies': [],
        'plugins': [],
        'description': txt('m:description')
    }

    # Core project props
    data['properties']['byteBuddyVersion'] = root.findtext('m:properties/m:byte-buddy.version', default='', namespaces=ns)
    data['properties']['derbyVersion']      = root.findtext('m:properties/m:derby.version',      default='', namespaces=ns)
    data['properties']['log4jVersion']     = root.findtext('m:properties/m:log4j.version',     default='', namespaces=ns)
    data['properties']['mockitoVersion']   = root.findtext('m:properties/m:mockito.version',   default='', namespaces=ns)
    data['properties']['mssqlJdbcVersion'] = root.findtext('m:properties/m:mssql-jdbc.version', default='', namespaces=ns)
    data['properties']['testcontainersVersion'] = root.findtext('m:properties/m:testcontainers.version', default='', namespaces=ns)
    data['properties']['gitBuildHookVersion']    = root.findtext('m:properties/m:git-build-hook.version', default='', namespaces=ns)
    # Java version
    data['properties']['javaVersion'] = root.findtext('m:properties/m:impsort.compliance', default='17', namespaces=ns)

    # Profiles for Derby
    for prof in root.findall('m:profiles/m:profile', ns):
        pid = prof.findtext('m:id', namespaces=ns)
        pder = prof.findtext('m:properties/m:derby.version', namespaces=ns)
        if pid and pder:
            data['profiles'][pid] = pder

    # Dependencies
    for d in root.findall('m:dependencies/m:dependency', ns):
        group = d.findtext('m:groupId', namespaces=ns)
        art   = d.findtext('m:artifactId', namespaces=ns)
        ver   = d.findtext('m:version',   namespaces=ns)
        scope = d.findtext('m:scope', default='compile', namespaces=ns)
        opt   = d.findtext('m:optional', default='false', namespaces=ns) == 'true'
        data['dependencies'].append({'g':group,'a':art,'v':ver,'s':scope,'o':opt})

    # Plugins
    for p in root.findall('m:build/m:plugins/m:plugin', ns):
        aid = p.findtext('m:artifactId', namespaces=ns)
        cfg = p.find('m:configuration', ns)
        data['plugins'].append({'id':aid, 'cfg':cfg})

    return data


def scope_map(dep):
    if dep['s']=='compile': return 'compileOnly' if dep['o'] else 'implementation'
    if dep['s']=='provided': return 'compileOnly'
    if dep['s']=='runtime':  return 'runtimeOnly'
    if dep['s']=='test':     return 'testImplementation'
    return 'implementation'


def generate_kts(d):
    p = d['properties']
    lines=[]
    # License block
    if d['license']:
        lines.append('/*')
        for l in d['license'].splitlines(): lines.append(f' *{l}')
        lines.append(' */\n')
    # Plugins
    lines += [
        'plugins {',
        '    java',
        '    jacoco',
        '    id("com.github.johnrengelman.shadow") version "8.1.1"',
        '}\n'
    ]
    # Versions
    lines += [
        f'val byteBuddyVersion = "{p["byteBuddyVersion"]}"',
        f'val derbyVersion      = "{p["derbyVersion"]}"',
        f'val log4jVersion     = "{p["log4jVersion"]}"',
        f'val mockitoVersion   = "{p["mockitoVersion"]}"',
        f'val mssqlJdbcVersion = "{p["mssqlJdbcVersion"]}"',
        f'val testcontainersVersion = "{p["testcontainersVersion"]}"',
        f'val gitBuildHookVersion    = "{p["gitBuildHookVersion"]}"',
        f'val javaVersion = JavaVersion.VERSION_{p["javaVersion"]}\n'
    ]
    # Java
    lines += [
        'java {',
        '    sourceCompatibility = javaVersion',
        '    targetCompatibility = javaVersion',
        '}\n'
    ]
    # Repos
    lines += ['repositories {','    mavenCentral()','}\n']
    # Dependencies
    lines.append('dependencies {')
    for dep in d['dependencies']:
        cfg=scope_map(dep)
        ver=f':{dep["v"]}' if dep['v'] else ''
        lines.append(f'    {cfg}("{dep["g"]}:{dep["a"]}{ver}")')
    lines.append('}\n')
    # Compile and Test tasks
    lines += [
        'tasks.withType<JavaCompile> { options.encoding = "UTF-8" }',
        'tasks.test {',
        '    useJUnitPlatform()',
        '    maxHeapSize = "2048m"',
        '    jvmArgs = listOf("-javaagent=${rootProject.buildDir}/libs/byte-buddy-agent-$byteBuddyVersion.jar")',
        '    systemProperty("derby.stream.error.file", "${buildDir}/derby.log")',
        '    systemProperty("derby.system.home", buildDir.toString())',
        '}\n'
    ]
    # ShadowJar
    lines += [
        'tasks.withType<com.github.jengelman.gradle.plugins.shadow.tasks.ShadowJar> {',
        '    archiveClassifier.set("")',
        '    mergeServiceFiles()',
        '    relocate("ognl","org.apache.ibatis.ognl")',
        '    relocate("javassist","org.apache.ibatis.javassist")',
        '    exclude("META-INF/MANIFEST.MF")',
        '}\n'
    ]
    # Jacoco
    lines += ['jacoco { toolVersion = "0.8.11" }\n']
    # Git Hook
    lines += [
        'tasks.register<Exec>("installGitHook") {',
        '    commandLine("bash","hooks/pre-commit.sh")',
        '}\n'
    ]
    # Description
    if d['description']:
        desc=d['description'].replace('"','\\"').replace('\n',' ')
        lines.append(f'description = "{desc}"\n')
    # Derby profiles
    d17=d['profiles'].get('17',p['derbyVersion'])
    d19=d['profiles'].get('19',p['derbyVersion'])
    lines += [
        'if (JavaVersion.current() >= JavaVersion.VERSION_17) {',
        f'    extra["derby.version"] = "{d17}"',
        '}',
        'if (JavaVersion.current().isCompatibleWith(JavaVersion.VERSION_19)) {',
        f'    extra["derby.version"] = "{d19}"',
        '}'
    ]
    return "\n".join(lines)


def main():
    if len(sys.argv)!=3:
        print("Usage: migrate_pom_to_gradle.py <pom.xml> <build.gradle.kts>")
        sys.exit(1)
    pom,out=sys.argv[1],sys.argv[2]
    data=parse_pom(pom)
    Path(out).write_text(generate_kts(data),encoding='utf-8')
    print(f"Generated: {out}")

if __name__=="__main__": main()
