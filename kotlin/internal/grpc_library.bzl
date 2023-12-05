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

"""Rules/macros for gRPC libraries."""

load("@rules_java//java:defs.bzl", "java_library")
load("//kotlin/internal:common.bzl", "create_srcjar", "get_real_short_path")
load("//kotlin/internal:library.bzl", "kt_jvm_library")
load("//kotlin/internal:proto_library.bzl", "kt_jvm_proto_library")

_KT_JVM_GRPC_DEPS = [
    Label("//imports/io/gprc:api"),
    Label("//imports/io/gprc/protobuf"),
    Label("//imports/io/gprc/stub"),
    Label("//imports/io/gprc/kotlin:stub"),
]

def _generate_java_grpc_extensions(
        ctx,
        protoc,
        grpc_java_plugin,
        proto_lib,
        output_dir):
    """Generates code for Kotlin proto extensions."""
    proto_info = proto_lib[ProtoInfo]
    srcs = proto_info.direct_sources
    transitive_descriptor_set = proto_info.transitive_descriptor_sets

    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    args.use_param_file("@%s")
    args.add_joined(
        transitive_descriptor_set,
        join_with = ctx.configuration.host_path_separator,
        format_joined = "--descriptor_set_in=%s",
    )
    args.add_all(srcs, map_each = get_real_short_path)
    args.add(
        grpc_java_plugin,
        format = "--plugin=protoc-gen-grpc-java=%s",
    )
    args.add("--grpc-java_out=" + output_dir.path)

    ctx.actions.run(
        inputs = depset(
            srcs,
            transitive = [transitive_descriptor_set],
        ),
        outputs = [output_dir],
        executable = protoc,
        arguments = [args],
        tools = [grpc_java_plugin],
        mnemonic = "JavaGrpcProtoc",
        progress_message = "Generating Java gRPC extensions for " + ctx.label.name,
        toolchain = None,
    )

def _generate_kotlin_grpc_extensions(
        ctx,
        grpc_kt_generator,
        proto_lib,
        output_dir):
    """Generates code for Kotlin gRPC extensions."""
    proto_info = proto_lib[ProtoInfo]
    direct_descriptor_set = proto_info.direct_descriptor_set
    transitive_descriptor_set = proto_info.transitive_descriptor_sets

    generator_args = ctx.actions.args()
    generator_args.add(output_dir.path)
    generator_args.add_all([direct_descriptor_set])
    generator_args.add("--")
    generator_args.add_all(transitive_descriptor_set)

    ctx.actions.run(
        inputs = depset(
            [direct_descriptor_set],
            transitive = [transitive_descriptor_set],
        ),
        outputs = [output_dir],
        arguments = [generator_args],
        executable = grpc_kt_generator,
        mnemonic = "KtGrpcGenerator",
        progress_message = "Generating Kotlin gRPC extensions for " + ctx.label.name,
        toolchain = None,
    )

def _kt_jvm_grpc_library_helper_impl(ctx):
    name = ctx.attr.name
    proto_dep = ctx.attr.proto_dep

    # TODO(@SanjayVas): Compile generated Java code, collecting JavaInfo.
    java_grpc_src_dir_name = name + "_java_grpc_srcs"
    java_grpc_src_dir = ctx.actions.declare_directory(java_grpc_src_dir_name)
    _generate_java_grpc_extensions(
        ctx,
        ctx.executable._protoc,
        ctx.executable._grpc_java_plugin,
        proto_dep,
        java_grpc_src_dir,
    )

    kt_grpc_src_dir_name = name + "_kt_jvm_grpc_srcs"
    kt_grpc_src_dir = ctx.actions.declare_directory(kt_grpc_src_dir_name)
    _generate_kotlin_grpc_extensions(
        ctx,
        ctx.executable._grpc_kt_generator,
        proto_dep,
        kt_grpc_src_dir,
    )

    create_srcjar(
        ctx,
        ctx.executable._zipper,
        ctx.outputs.srcjar,
        java_grpc_src_dir,
        kt_grpc_src_dir,
    )

_kt_jvm_grpc_library_helper = rule(
    implementation = _kt_jvm_grpc_library_helper_impl,
    attrs = {
        "proto_dep": attr.label(
            providers = [ProtoInfo],
            mandatory = True,
        ),
        "srcjar": attr.output(
            doc = "Generated Java source jar.",
            mandatory = True,
        ),
        "_zipper": attr.label(
            default = Label("@bazel_tools//tools/zip:zipper"),
            cfg = "exec",
            executable = True,
        ),
        "_protoc": attr.label(
            default = Label("@com_google_protobuf//:protoc"),
            cfg = "exec",
            executable = True,
        ),
        "_grpc_kt_generator": attr.label(
            default = Label(":KotlinGrpcGenerator"),
            cfg = "exec",
            executable = True,
        ),
        "_grpc_java_plugin": attr.label(
            default = Label(":protoc_gen_grpc_java"),
            cfg = "exec",
            executable = True,
        ),
    },
)

def kt_jvm_grpc_library(
        name,
        srcs = None,
        deps = None,
        visibility = None,
        **kwargs):
    """Generates and compiles gRPC extensions from a proto_library.

    Args:
      name: a name for the target
      srcs: exactly one proto_library target
      deps: exactly one JVM proto_library target for srcs, e.g. a kt_jvm_proto_library
      visibility: standard visibility attribute
      **kwargs: additional arguments for resulting target
    """
    srcs = srcs or []
    deps = deps or []
    if len(srcs) != 1:
        fail("Expected exactly one src", "srcs")
    if len(deps) != 1:
        fail("Expected exactly one dep", "deps")

    helper_name = name + "_DO_NOT_DEPEND_kt_jvm_grpc_gen"
    srcjar_name = helper_name + ".srcjar"
    _kt_jvm_grpc_library_helper(
        name = helper_name,
        proto_dep = srcs[0],
        srcjar = srcjar_name,
        visibility = ["//visibility:private"],
        **kwargs
    )

    kt_jvm_library(
        name = name,
        srcs = [":" + srcjar_name],
        deps = deps + _KT_JVM_GRPC_DEPS,
        exports = _KT_JVM_GRPC_DEPS,
        visibility = visibility,
        kotlinc_opts = Label(":proto_gen_kt_options"),
        **kwargs
    )

_PROTO_LIBRARY_SUFFIX = "_proto"

def kt_jvm_grpc_proto_library(name, deps = None, **kwargs):
    """Wrapper for generating Kotlin JVM protobuf APIs and gRPC extensions.

    Given a proto_library named `<prefix>_proto`, this will create additional
    `<prefix>_kt_jvm_proto` and `<prefix>_kt_jvm_grpc` targets.

    Args:
      name: a name for the target
      deps: exactly one proto_library target
      **kwargs: other args to pass to the resulting target
    """
    deps = deps or []
    if len(deps) != 1:
        fail("Expected exactly one dep", "deps")

    proto_label = native.package_relative_label(deps[0])
    proto_name = proto_label.name
    if not proto_name.endswith(_PROTO_LIBRARY_SUFFIX):
        fail("proto_library target names should end with '{suffix}'".format(
            suffix = _PROTO_LIBRARY_SUFFIX,
        ))
    name_prefix = proto_label.name.removesuffix(_PROTO_LIBRARY_SUFFIX)

    kt_jvm_proto_name = name_prefix + "_kt_jvm_proto"
    kt_jvm_proto_label = ":" + kt_jvm_proto_name
    kt_jvm_proto_library(
        name = kt_jvm_proto_name,
        deps = deps,
        **kwargs
    )

    kt_jvm_grpc_name = name_prefix + "_kt_jvm_grpc"
    kt_jvm_grpc_label = ":" + kt_jvm_grpc_name
    kt_jvm_grpc_library(
        name = kt_jvm_grpc_name,
        srcs = deps,
        deps = [kt_jvm_proto_label],
        **kwargs
    )

    java_library(
        name = name,
        exports = [
            kt_jvm_proto_label,
            kt_jvm_grpc_label,
        ],
        **kwargs
    )
