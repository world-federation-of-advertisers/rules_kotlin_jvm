# Copyright 2021 The Cross-Media Measurement Authors
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

"""
Provides kt_jvm_proto_library to generate Kotlin protos.
"""

load("@com_google_protobuf//bazel:java_proto_library.bzl", "java_proto_library")
load("@com_google_protobuf//bazel/common:proto_info.bzl", "ProtoInfo")
load(
    "//kotlin/internal:common.bzl",
    "create_srcjar",
    "get_real_short_path",
    "merge_srcjars",
)
load("//kotlin/internal:library.bzl", "kt_jvm_library")

KtProtoLibInfo = provider(
    "Information for a Kotlin JVM proto library.",
    fields = {
        "srcjars": "depset of .srcjar Files",
    },
)

def _generate_kotlin_proto_extensions(ctx, protoc, proto_lib, output_dir):
    """Generates code for Kotlin proto extensions."""
    proto_info = proto_lib[ProtoInfo]
    srcs = proto_info.direct_sources
    transitive_descriptor_set = proto_info.transitive_descriptor_sets

    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    args.use_param_file("@%s")
    args.add("--kotlin_out=" + output_dir.path)
    args.add_joined(
        transitive_descriptor_set,
        join_with = ctx.configuration.host_path_separator,
        format_joined = "--descriptor_set_in=%s",
    )
    args.add_all(srcs, map_each = get_real_short_path)

    ctx.actions.run(
        inputs = depset(srcs, transitive = [transitive_descriptor_set]),
        outputs = [output_dir],
        executable = protoc,
        arguments = [args],
        mnemonic = "KtProtoc",
        progress_message = "Generating Kotlin protobuf extensions for " + ctx.label.name,
        toolchain = None,
    )

def _kt_jvm_proto_aspect_impl(target, ctx):
    name = target.label.name

    gen_src_dir_name = name + "_kt_jvm_srcs"
    gen_src_dir = ctx.actions.declare_directory(gen_src_dir_name)
    _generate_kotlin_proto_extensions(
        ctx,
        ctx.executable._protoc,
        target,
        gen_src_dir,
    )

    srcjar_name = name + "_kt_jvm.srcjar"
    srcjar = ctx.actions.declare_file(srcjar_name)
    create_srcjar(ctx, ctx.executable._zipper, srcjar, gen_src_dir)

    transitive = [
        dep[KtProtoLibInfo].srcjars
        for dep in ctx.rule.attr.deps
        if KtProtoLibInfo in dep
    ]
    return [KtProtoLibInfo(
        srcjars = depset(direct = [srcjar], transitive = transitive),
    )]

_kt_jvm_proto_aspect = aspect(
    attrs = {
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
    },
    implementation = _kt_jvm_proto_aspect_impl,
    attr_aspects = ["deps"],
)

def _kt_jvm_proto_library_helper_impl(ctx):
    """Implementation of _kt_jvm_proto_library_helper rule."""
    proto_lib_info = ctx.attr.proto_dep[KtProtoLibInfo]
    merge_srcjars(
        ctx,
        ctx.executable._zipper,
        ctx.executable._extract_srcjars,
        ctx.outputs.srcjar,
        *proto_lib_info.srcjars.to_list()
    )

_kt_jvm_proto_library_helper = rule(
    doc = """
    Helper rule for generating Kotlin JVM proto APIs.
    
    This calls protoc with the `--kotlin_out` flag and collects the outputs into
    a srcjar.
    
    TODO(bazelbuild/rules_kotlin#1076): Have this actually compile the code as well. 
    """,
    attrs = {
        "proto_dep": attr.label(
            providers = [ProtoInfo],
            aspects = [_kt_jvm_proto_aspect],
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
        "_extract_srcjars": attr.label(
            default = Label(":extract_srcjars"),
            cfg = "exec",
            executable = True,
        ),
    },
    implementation = _kt_jvm_proto_library_helper_impl,
)

_KT_JVM_PROTO_DEPS = [
    Label("//imports/com/google/protobuf/kotlin"),
]

def kt_jvm_proto_library(
        name,
        deps = None,
        **kwargs):
    """Generates and compiles Java and Kotlin APIs for a proto_library.

    For standard attributes, see:
      https://docs.bazel.build/versions/master/be/common-definitions.html#common-attributes

    Args:
      name: A name for the target
      deps: Exactly one proto_library target to generate Kotlin APIs for
      **kwargs: other args to pass to the ultimate kt_jvm_library target
    """
    deps = deps or []

    if len(deps) != 1:
        fail("Expected exactly one dep", "deps")

    java_name = name + "_DO_NOT_DEPEND_java_proto"
    java_label = ":" + java_name
    java_proto_library(
        name = java_name,
        deps = deps,
        visibility = ["//visibility:private"],
    )
    kt_jvm_deps = _KT_JVM_PROTO_DEPS + [java_label]

    generated_kt_name = name + "_DO_NOT_DEPEND_generated_kt"
    generated_srcjar = generated_kt_name + ".srcjar"
    _kt_jvm_proto_library_helper(
        name = generated_kt_name,
        proto_dep = deps[0],
        srcjar = generated_srcjar,
        visibility = ["//visibility:private"],
    )

    kt_jvm_library(
        name = name,
        srcs = [generated_srcjar],
        deps = kt_jvm_deps,
        exports = kt_jvm_deps,
        kotlinc_opts = Label(":proto_gen_kt_options"),
        **kwargs
    )
