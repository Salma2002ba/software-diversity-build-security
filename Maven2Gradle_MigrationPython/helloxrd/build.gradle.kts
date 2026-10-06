/*
 *! Licensed to the Apache Software Foundation (ASF) under one or more
 * ! contributor license agreements.  See the NOTICE file distributed with
 * ! this work for additional information regarding copyright ownership.
 * ! The ASF licenses this file to You under the Apache License, Version 2.0
 * ! (the "License"); you may not use this file except in compliance with
 * ! the License.  You may obtain a copy of the License at
 * !
 * !      http://www.apache.org/licenses/LICENSE-2.0
 * !
 * ! Unless required by applicable law or agreed to in writing, software
 * ! distributed under the License is distributed on an "AS IS" BASIS,
 * ! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * ! See the License for the specific language governing permissions and
 * ! limitations under the License.
 * !
 */

plugins {
    java
    jacoco
    id("com.github.johnrengelman.shadow") version "8.1.1"
}

val byteBuddyVersion = ""
val derbyVersion      = ""
val log4jVersion     = ""
val mockitoVersion   = ""
val mssqlJdbcVersion = ""
val testcontainersVersion = ""
val gitBuildHookVersion    = ""
val javaVersion = JavaVersion.VERSION_17

java {
    sourceCompatibility = javaVersion
    targetCompatibility = javaVersion
}

repositories {
    mavenCentral()
}

dependencies {
    implementation("${project.groupId}:pdfbox-tools:${project.version}")
    implementation("org.bouncycastle:bcpkix-jdk18on:${bouncycastle.version}")
    implementation("org.bouncycastle:bcprov-jdk18on:${bouncycastle.version}")
}

tasks.withType<JavaCompile> { options.encoding = "UTF-8" }
tasks.test {
    useJUnitPlatform()
    maxHeapSize = "2048m"
    jvmArgs = listOf("-javaagent=${rootProject.buildDir}/libs/byte-buddy-agent-$byteBuddyVersion.jar")
    systemProperty("derby.stream.error.file", "${buildDir}/derby.log")
    systemProperty("derby.system.home", buildDir.toString())
}

tasks.withType<com.github.jengelman.gradle.plugins.shadow.tasks.ShadowJar> {
    archiveClassifier.set("")
    mergeServiceFiles()
    relocate("ognl","org.apache.ibatis.ognl")
    relocate("javassist","org.apache.ibatis.javassist")
    exclude("META-INF/MANIFEST.MF")
}

jacoco { toolVersion = "0.8.11" }

tasks.register<Exec>("installGitHook") {
    commandLine("bash","hooks/pre-commit.sh")
}

if (JavaVersion.current() >= JavaVersion.VERSION_17) {
    extra["derby.version"] = ""
}
if (JavaVersion.current().isCompatibleWith(JavaVersion.VERSION_19)) {
    extra["derby.version"] = ""
}