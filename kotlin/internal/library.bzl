# Copyright 2023 The Cross-Media Measurement Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Rules/macros for Kotlin JVM library."""

load(
    "@rules_kotlin//kotlin:jvm.bzl",
    _kt_jvm_library = "kt_jvm_library",
)

_STDLIBS = [
    Label("//imports/kotlin:stdlib"),
    Label("//imports/kotlin/reflect"),
]

def kt_jvm_library(
        name,
        deps = None,
        exports = None,
        **kwargs):
    deps = deps or []
    exports = exports or []

    _kt_jvm_library(
        name = name,
        deps = deps + _STDLIBS,
        exports = exports + _STDLIBS,
        **kwargs
    )
