# Copyright 2023 The Cross-Media Measurement Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Rules and macros for Kotlin JVM."""

load(
    "@rules_kotlin//kotlin:jvm.bzl",
    _kt_jvm_binary = "kt_jvm_binary",
    _kt_jvm_test = "kt_jvm_test",
)
load(
    "//kotlin/internal:grpc_library.bzl",
    _kt_jvm_grpc_library = "kt_jvm_grpc_library",
    _kt_jvm_grpc_proto_library = "kt_jvm_grpc_proto_library",
)
load(
    "//kotlin/internal:library.bzl",
    _kt_jvm_library = "kt_jvm_library",
)
load(
    "//kotlin/internal:proto_library.bzl",
    _kt_jvm_proto_library = "kt_jvm_proto_library",
)

kt_jvm_library = _kt_jvm_library
kt_jvm_test = _kt_jvm_test
kt_jvm_binary = _kt_jvm_binary
kt_jvm_proto_library = _kt_jvm_proto_library
kt_jvm_grpc_library = _kt_jvm_grpc_library
kt_jvm_grpc_proto_library = _kt_jvm_grpc_proto_library
