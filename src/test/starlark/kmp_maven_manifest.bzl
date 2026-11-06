"""A manifest of bazel-kmp-resolver for the tests of kmp_maven: an excerpt of its testResources/manifest-all_platforms.json.

The resolution of org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2 by bazel-kmp-resolver 039a4dc, with the
ios_arm64, linux_x64, android and jvm variants of its four libraries, the askedPlatforms of those platforms, and
the wasm_js variant of coroutines, which rules_kotlin skips.
"""

COROUTINES_MANIFEST = """{
  "schemaVersion": 2,
  "resolverVersion": "dev",
  "inputsHash": "4e5edb31b791efb172a39571452fe731c8625a0201aec4186b6f22bba3600416",
  "askedPlatforms": ["ios_arm64", "linux_x64", "android", "jvm"],
  "askedCoordinates": ["org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2"],
  "askedRepositories": ["https://repo1.maven.org/maven2"],
  "askedSubstitutions": [],
  "libraries": {
    "org.jetbrains.kotlin:kotlin-stdlib:2.1.0": {
      "id": "org.jetbrains.kotlin:kotlin-stdlib:2.1.0",
      "variants": [
        {
          "type": "android",
          "id": "org.jetbrains.kotlin:kotlin-stdlib:2.1.0",
          "variantId": "org.jetbrains.kotlin:kotlin-stdlib:2.1.0",
          "dependencies": [],
          "exportedDependencies": ["org.jetbrains:annotations"],
          "artifact": {"integrity": "sha512-GFBJ0x6Ca3Gi8TXhnj6PuyK8MAMr+gFfFvDif0CWH7D2sYZwkMbImFE/SR7QPwFKjhXAetq4CqelcZ6Y2nhGpQ==", "groupId": "org.jetbrains.kotlin", "artifactId": "kotlin-stdlib", "version": "2.1.0", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/kotlin/kotlin-stdlib/2.1.0/kotlin-stdlib-2.1.0.jar"]},
          "packaging": "jar",
          "sourceJar": {"integrity": "sha512-8jfMR/JQMNLnve3ZtfdjYdPJPlS6vuJal6/P4BviKEJDgbQ4Sq2Om8kLsOC/4gM/kP6s4ulurJX1hEm4CJrRbg==", "groupId": "org.jetbrains.kotlin", "artifactId": "kotlin-stdlib", "version": "2.1.0", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/kotlin/kotlin-stdlib/2.1.0/kotlin-stdlib-2.1.0-sources.jar"]}
        },
        {
          "type": "jvm",
          "id": "org.jetbrains.kotlin:kotlin-stdlib:2.1.0",
          "variantId": "org.jetbrains.kotlin:kotlin-stdlib:2.1.0",
          "dependencies": [],
          "exportedDependencies": ["org.jetbrains:annotations"],
          "jar": {"integrity": "sha512-GFBJ0x6Ca3Gi8TXhnj6PuyK8MAMr+gFfFvDif0CWH7D2sYZwkMbImFE/SR7QPwFKjhXAetq4CqelcZ6Y2nhGpQ==", "groupId": "org.jetbrains.kotlin", "artifactId": "kotlin-stdlib", "version": "2.1.0", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/kotlin/kotlin-stdlib/2.1.0/kotlin-stdlib-2.1.0.jar"]},
          "sourceJar": {"integrity": "sha512-8jfMR/JQMNLnve3ZtfdjYdPJPlS6vuJal6/P4BviKEJDgbQ4Sq2Om8kLsOC/4gM/kP6s4ulurJX1hEm4CJrRbg==", "groupId": "org.jetbrains.kotlin", "artifactId": "kotlin-stdlib", "version": "2.1.0", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/kotlin/kotlin-stdlib/2.1.0/kotlin-stdlib-2.1.0-sources.jar"]}
        }
      ]
    },
    "org.jetbrains.kotlinx:atomicfu:0.26.1": {
      "id": "org.jetbrains.kotlinx:atomicfu:0.26.1",
      "variants": [
        {
          "type": "klib",
          "platform": "ios_arm64",
          "id": "org.jetbrains.kotlinx:atomicfu:0.26.1",
          "variantId": "org.jetbrains.kotlinx:atomicfu-iosarm64:0.26.1",
          "dependencies": [],
          "exportedDependencies": [],
          "klibs": [
            {
              "role": "main",
              "artifact": {"integrity": "sha512-q6hU+NRTgZd0qA+gBzUQyqKIOztGgCXP1SBhbjpRBuFvu1WcA1dKN3PLMnDP3j2Wt/bfLlvc4msKX36iY90a8w==", "groupId": "org.jetbrains.kotlinx", "artifactId": "atomicfu-iosarm64", "version": "0.26.1", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/kotlinx/atomicfu-iosarm64/0.26.1/atomicfu-iosarm64-0.26.1.klib"]}
            },
            {
              "role": "cinterop",
              "artifact": {"integrity": "sha512-JRXxIoPCmAoerWxIPlzyLXQknKT1AEjmD8OEb6kxDiDDSTgOwejqziwo7yuPvKxU7ljCZW4fQgdRAr17W5f81w==", "groupId": "org.jetbrains.kotlinx", "artifactId": "atomicfu-iosarm64", "version": "0.26.1", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/kotlinx/atomicfu-iosarm64/0.26.1/atomicfu-iosarm64-0.26.1-cinterop-interop.klib"]}
            }
          ],
          "sourceJar": {"integrity": "sha512-+3B8ysTAWtO938STQiEyi+KZVf3fY//RekAwsDoToVR8J2+ei7uojz8jXRTFuCOsrIIKUiod1ij05hx1p2cPyw==", "groupId": "org.jetbrains.kotlinx", "artifactId": "atomicfu-iosarm64", "version": "0.26.1", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/kotlinx/atomicfu-iosarm64/0.26.1/atomicfu-iosarm64-0.26.1-sources.jar"]}
        },
        {
          "type": "klib",
          "platform": "linux_x64",
          "id": "org.jetbrains.kotlinx:atomicfu:0.26.1",
          "variantId": "org.jetbrains.kotlinx:atomicfu-linuxx64:0.26.1",
          "dependencies": [],
          "exportedDependencies": [],
          "klibs": [
            {
              "role": "main",
              "artifact": {"integrity": "sha512-mGZoVQm7IdRmlCiJ7p1+lcWMw+utIyIiqnf8C3I4rhddV2jlsMUEHdG6ojrBmrwk7kn+SpUsBOFGp36IlQO4og==", "groupId": "org.jetbrains.kotlinx", "artifactId": "atomicfu-linuxx64", "version": "0.26.1", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/kotlinx/atomicfu-linuxx64/0.26.1/atomicfu-linuxx64-0.26.1.klib"]}
            },
            {
              "role": "cinterop",
              "artifact": {"integrity": "sha512-Bvbj9pRIzj7yTGj+2I5bvmDLV0IiFKK6lgale+zmc8CSOlqILavgGP1d+u4bcIZONNIvEoMq+Z8m5PUfvtabUg==", "groupId": "org.jetbrains.kotlinx", "artifactId": "atomicfu-linuxx64", "version": "0.26.1", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/kotlinx/atomicfu-linuxx64/0.26.1/atomicfu-linuxx64-0.26.1-cinterop-interop.klib"]}
            }
          ],
          "sourceJar": {"integrity": "sha512-cA2AbRuudO9D7SZGXn4yWxkLluWTyEYOPI6UfiNDC/YR78UNTy7NksV+zYN4ZifVgbz4NiuXV9bMK0vBinOmGg==", "groupId": "org.jetbrains.kotlinx", "artifactId": "atomicfu-linuxx64", "version": "0.26.1", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/kotlinx/atomicfu-linuxx64/0.26.1/atomicfu-linuxx64-0.26.1-sources.jar"]}
        }
      ]
    },
    "org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2": {
      "id": "org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2",
      "variants": [
        {
          "type": "klib",
          "platform": "wasm_js",
          "id": "org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2",
          "variantId": "org.jetbrains.kotlinx:kotlinx-coroutines-core-wasm-js:1.10.2",
          "dependencies": [],
          "exportedDependencies": ["org.jetbrains.kotlin:kotlin-stdlib", "org.jetbrains.kotlinx:atomicfu"],
          "klibs": [
            {
              "role": "main",
              "artifact": {"integrity": "sha512-8SphTDxmXU+XVBvoED1QuRvjICXgs65zKoYAzJRDbkoxmam3aP2k55kDm96enA62ow/h3aMJWu7Ojmdh0VkY3w==", "groupId": "org.jetbrains.kotlinx", "artifactId": "kotlinx-coroutines-core-wasm-js", "version": "1.10.2", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/kotlinx/kotlinx-coroutines-core-wasm-js/1.10.2/kotlinx-coroutines-core-wasm-js-1.10.2.klib"]}
            }
          ],
          "sourceJar": {"integrity": "sha512-5n2MXwJ8W7vXRqStmNtfOIIGQD6kp4Y1U2KmE9BKsIB9LBfhXUSOUt5LsQziJBC/7FfkmfCqkLrUHfC8XA2/8w==", "groupId": "org.jetbrains.kotlinx", "artifactId": "kotlinx-coroutines-core-wasm-js", "version": "1.10.2", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/kotlinx/kotlinx-coroutines-core-wasm-js/1.10.2/kotlinx-coroutines-core-wasm-js-1.10.2-sources.jar"]}
        },
        {
          "type": "klib",
          "platform": "ios_arm64",
          "id": "org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2",
          "variantId": "org.jetbrains.kotlinx:kotlinx-coroutines-core-iosarm64:1.10.2",
          "dependencies": [],
          "exportedDependencies": ["org.jetbrains.kotlinx:atomicfu"],
          "klibs": [
            {
              "role": "main",
              "artifact": {"integrity": "sha512-ujOAPZwU/UB7M1vMcmbUdqEPHpeMS3CKIGqc/9f9NvBzqPss+tBJ4XeBdiAnHJqfxnjBHFzOOjU8PT1OpJjlzg==", "groupId": "org.jetbrains.kotlinx", "artifactId": "kotlinx-coroutines-core-iosarm64", "version": "1.10.2", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/kotlinx/kotlinx-coroutines-core-iosarm64/1.10.2/kotlinx-coroutines-core-iosarm64-1.10.2.klib"]}
            }
          ],
          "sourceJar": {"integrity": "sha512-4JN9fgX3aYH4LKXNL4g+cb6Cd0BSX6J004w3NswrEOnsjzp/Y+8RuWPN8J/B311UC2q1bhgCVYBgDHcZb1eb9w==", "groupId": "org.jetbrains.kotlinx", "artifactId": "kotlinx-coroutines-core-iosarm64", "version": "1.10.2", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/kotlinx/kotlinx-coroutines-core-iosarm64/1.10.2/kotlinx-coroutines-core-iosarm64-1.10.2-sources.jar"]}
        },
        {
          "type": "klib",
          "platform": "linux_x64",
          "id": "org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2",
          "variantId": "org.jetbrains.kotlinx:kotlinx-coroutines-core-linuxx64:1.10.2",
          "dependencies": [],
          "exportedDependencies": ["org.jetbrains.kotlinx:atomicfu"],
          "klibs": [
            {
              "role": "main",
              "artifact": {"integrity": "sha512-7aupeYXcYJlsAp9CYYT2D1ZFTB0qKpWc/CPBPRN6J6z4vWiiFdYgT2CF1oXlI3lxcYnwHXW/UpE8RaV3fGSSYg==", "groupId": "org.jetbrains.kotlinx", "artifactId": "kotlinx-coroutines-core-linuxx64", "version": "1.10.2", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/kotlinx/kotlinx-coroutines-core-linuxx64/1.10.2/kotlinx-coroutines-core-linuxx64-1.10.2.klib"]}
            }
          ],
          "sourceJar": {"integrity": "sha512-NtboovXiTn1piAXHAWwWsEnGCGvvhMIbl3UCe6ml/tIEErozbvlUJ82rAAA62UX3gR8mikEnHA+yp3UclL6l6A==", "groupId": "org.jetbrains.kotlinx", "artifactId": "kotlinx-coroutines-core-linuxx64", "version": "1.10.2", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/kotlinx/kotlinx-coroutines-core-linuxx64/1.10.2/kotlinx-coroutines-core-linuxx64-1.10.2-sources.jar"]}
        },
        {
          "type": "android",
          "id": "org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2",
          "variantId": "org.jetbrains.kotlinx:kotlinx-coroutines-core-jvm:1.10.2",
          "dependencies": [],
          "exportedDependencies": ["org.jetbrains.kotlin:kotlin-stdlib", "org.jetbrains:annotations"],
          "artifact": {"integrity": "sha512-I4/UUfgOIiSAyIDdi8/XbpIDtoM6AwalVIOz+esLJWUSQqPnvq91ENXjmSLx09mH/KeUaNlF6zWw8HFWp4h7oA==", "groupId": "org.jetbrains.kotlinx", "artifactId": "kotlinx-coroutines-core-jvm", "version": "1.10.2", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/kotlinx/kotlinx-coroutines-core-jvm/1.10.2/kotlinx-coroutines-core-jvm-1.10.2.jar"]},
          "packaging": "jar",
          "sourceJar": {"integrity": "sha512-ZNo9M9348wxSfmUiwJAnaBWOeEAzuFuwM+WW38KXYfWMzCQKjI1/4qOovkwVNcmUAWKfrm+cMrQrrBKq/4TXzg==", "groupId": "org.jetbrains.kotlinx", "artifactId": "kotlinx-coroutines-core-jvm", "version": "1.10.2", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/kotlinx/kotlinx-coroutines-core-jvm/1.10.2/kotlinx-coroutines-core-jvm-1.10.2-sources.jar"]}
        },
        {
          "type": "jvm",
          "id": "org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2",
          "variantId": "org.jetbrains.kotlinx:kotlinx-coroutines-core-jvm:1.10.2",
          "dependencies": [],
          "exportedDependencies": ["org.jetbrains.kotlin:kotlin-stdlib", "org.jetbrains:annotations"],
          "jar": {"integrity": "sha512-I4/UUfgOIiSAyIDdi8/XbpIDtoM6AwalVIOz+esLJWUSQqPnvq91ENXjmSLx09mH/KeUaNlF6zWw8HFWp4h7oA==", "groupId": "org.jetbrains.kotlinx", "artifactId": "kotlinx-coroutines-core-jvm", "version": "1.10.2", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/kotlinx/kotlinx-coroutines-core-jvm/1.10.2/kotlinx-coroutines-core-jvm-1.10.2.jar"]},
          "sourceJar": {"integrity": "sha512-ZNo9M9348wxSfmUiwJAnaBWOeEAzuFuwM+WW38KXYfWMzCQKjI1/4qOovkwVNcmUAWKfrm+cMrQrrBKq/4TXzg==", "groupId": "org.jetbrains.kotlinx", "artifactId": "kotlinx-coroutines-core-jvm", "version": "1.10.2", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/kotlinx/kotlinx-coroutines-core-jvm/1.10.2/kotlinx-coroutines-core-jvm-1.10.2-sources.jar"]}
        }
      ]
    },
    "org.jetbrains:annotations:23.0.0": {
      "id": "org.jetbrains:annotations:23.0.0",
      "variants": [
        {
          "type": "android",
          "id": "org.jetbrains:annotations:23.0.0",
          "variantId": "org.jetbrains:annotations:23.0.0",
          "dependencies": [],
          "exportedDependencies": [],
          "artifact": {"integrity": "sha1-jMIMB1BuwY4INJR7hKhkv8CUSE4=", "groupId": "org.jetbrains", "artifactId": "annotations", "version": "23.0.0", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/annotations/23.0.0/annotations-23.0.0.jar"]},
          "packaging": "jar",
          "sourceJar": {"integrity": "sha1-ylCI1hWsyqvSqpVrELI2pOdc/Ms=", "groupId": "org.jetbrains", "artifactId": "annotations", "version": "23.0.0", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/annotations/23.0.0/annotations-23.0.0-sources.jar"]}
        },
        {
          "type": "jvm",
          "id": "org.jetbrains:annotations:23.0.0",
          "variantId": "org.jetbrains:annotations:23.0.0",
          "dependencies": [],
          "exportedDependencies": [],
          "jar": {"integrity": "sha1-jMIMB1BuwY4INJR7hKhkv8CUSE4=", "groupId": "org.jetbrains", "artifactId": "annotations", "version": "23.0.0", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/annotations/23.0.0/annotations-23.0.0.jar"]},
          "sourceJar": {"integrity": "sha1-ylCI1hWsyqvSqpVrELI2pOdc/Ms=", "groupId": "org.jetbrains", "artifactId": "annotations", "version": "23.0.0", "urls": ["https://repo1.maven.org/maven2/org/jetbrains/annotations/23.0.0/annotations-23.0.0-sources.jar"]}
        }
      ]
    }
  }
}"""
