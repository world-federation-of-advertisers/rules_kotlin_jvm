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

load("@io_grpc_grpc_java//:java_grpc_library.bzl", "java_grpc_library")
load("@rules_java//java:defs.bzl", "java_proto_library")
load("@rules_proto//proto:defs.bzl", "ProtoInfo")
load("//kotlin/internal:library.bzl", "kt_jvm_library")

KtProtoLibInfo = provider(
    "Information for a Kotlin JVM proto library.",
    fields = {
        "srcjars": "depset of .srcjar Files",
    },
)

def get_real_short_path(file):
    """Returns the correct short path for a `File`.

    Args:
        file: the `File` to return the short path for.

    Returns:
        The short path for `file`, handling any non-standard path segments if
        it's from external repositories.
    """

    # For some reason, files from other archives have short paths that look like:
    #   ../com_google_protobuf/google/protobuf/descriptor.proto
    short_path = file.short_path
    if short_path.startswith("../"):
        second_slash = short_path.index("/", 3)
        short_path = short_path[second_slash + 1:]

    # Sometimes it has another few prefixes like:
    #   _virtual_imports/any_proto/google/protobuf/any.proto
    #   benchmarks/_virtual_imports/100_msgs_proto/benchmarks/100_msgs.proto
    # We want just google/protobuf/any.proto.
    virtual_imports = "_virtual_imports/"
    if virtual_imports in short_path:
        short_path = short_path.split(virtual_imports)[1].split("/", 1)[1]
    return short_path

def _generate_proto_extensions(ctx, proto_lib, output_dir):
    """Generates code for Kotlin proto extensions."""
    proto_info = proto_lib[ProtoInfo]
    transitive_descriptor_set = depset(transitive = [proto_info.transitive_descriptor_sets])
    proto_sources = [get_real_short_path(file) for file in proto_info.direct_sources]

    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    args.use_param_file("@%s")
    args.add("--kotlin_out=" + output_dir.path)
    args.add_joined(
        transitive_descriptor_set,
        join_with = ctx.configuration.host_path_separator,
        format_joined = "--descriptor_set_in=%s",
    )
    args.add_all(proto_sources)

    ctx.actions.run(
        inputs = depset(transitive = [transitive_descriptor_set]),
        outputs = [output_dir],
        executable = ctx.executable._protoc,
        arguments = [args],
        mnemonic = "KtProtoc",
        progress_message = "Generating Kotlin protobuf extensions for " + ctx.label.name,
    )

def _generate_grpc_extensions(ctx, proto_lib, output_dir):
    """Generates code for Kotlin gRPC extensions."""
    proto_info = proto_lib[ProtoInfo]
    direct_descriptor_set = depset([proto_info.direct_descriptor_set])
    transitive_descriptor_set = depset(transitive = [proto_info.transitive_descriptor_sets])

    generator_args = ctx.actions.args()
    generator_args.add(output_dir.path)
    generator_args.add_all(direct_descriptor_set)
    generator_args.add("--")
    generator_args.add_all(transitive_descriptor_set)

    ctx.actions.run(
        inputs = depset(transitive = [direct_descriptor_set, transitive_descriptor_set]),
        outputs = [output_dir],
        arguments = [generator_args],
        executable = ctx.executable._grpc_generator,
        mnemonic = "KtGrpcGenerator",
        progress_message = "Generating Kotlin gRPC extensions for " + ctx.label.name,
    )

def _create_srcjar(ctx, input_dir, output_jar):
    """Bundles .kt files into a srcjar."""
    zipper_args = ctx.actions.args()
    zipper_args.add("c", output_jar)
    zipper_args.add_all([input_dir])

    ctx.actions.run(
        outputs = [output_jar],
        inputs = [input_dir],
        executable = ctx.executable._zipper,
        arguments = [zipper_args],
        mnemonic = "KtProtoSrcJar",
        progress_message = "Generating Kotlin proto srcjar for " + ctx.label.name,
    )

def _merge_srcjars(ctx, input_jars, output_jar):
    """Merges multiple srcjars into a single srcjar."""
    tmp_dir_name = ctx.label.name + "_srcjars"
    tmp_dir = ctx.actions.declare_directory(tmp_dir_name)

    merge_args = ctx.actions.args()
    merge_args.add(ctx.executable._zipper)
    merge_args.add(tmp_dir.path)
    merge_args.add_all(input_jars)

    ctx.actions.run(
        outputs = [tmp_dir],
        inputs = input_jars,
        executable = ctx.executable._extract_srcjars,
        tools = [ctx.executable._zipper],
        arguments = [merge_args],
        mnemonic = "KtProtoExtractSrcJars",
    )

    _create_srcjar(ctx, tmp_dir, output_jar)

def _kt_jvm_proto_aspect_impl(target, ctx):
    name = target.label.name
    srcjars = []

    gen_src_dir_name = name + "_kt_jvm_srcs"
    gen_src_dir = ctx.actions.declare_directory(gen_src_dir_name)
    _generate_proto_extensions(ctx, target, gen_src_dir)

    srcjar_name = name + "_kt_jvm.srcjar"
    srcjar = ctx.actions.declare_file(srcjar_name)
    _create_srcjar(ctx, gen_src_dir, srcjar)
    srcjars.append(srcjar)

    if ctx.attr.has_services:
        gen_grpc_src_dir_name = name + "_kt_jvm_grpc_srcs"
        gen_grpc_src_dir = ctx.actions.declare_directory(gen_grpc_src_dir_name)
        _generate_grpc_extensions(ctx, target, gen_grpc_src_dir)

        grpc_srcjar_name = "_kt_jvm_grpc.srcjar"
        grpc_srcjar = ctx.actions.declare_file(grpc_srcjar_name)
        _create_srcjar(ctx, gen_grpc_src_dir, grpc_srcjar)
        srcjars.append(grpc_srcjar)

    transitive = [
        dep[KtProtoLibInfo].srcjars
        for dep in ctx.rule.attr.deps
        if KtProtoLibInfo in dep
    ]
    return [KtProtoLibInfo(
        srcjars = depset(direct = srcjars, transitive = transitive),
    )]

_kt_jvm_proto_aspect = aspect(
    attrs = {
        "has_services": attr.bool(
            default = False,
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
        "_grpc_generator": attr.label(
            default = Label(":KotlinGrpcGenerator"),
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
    _merge_srcjars(ctx, proto_lib_info.srcjars, ctx.outputs.srcjar)

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
        "has_services": attr.bool(
            default = False,
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
    Label("//imports/com/google/protobuf:kotlin"),
]

def kt_jvm_proto_library(
        name,
        deps = None,
        has_services = False,
        **kwargs):
    """Generates and compiles Java and Kotlin APIs for a proto_library.

    For standard attributes, see:
      https://docs.bazel.build/versions/master/be/common-definitions.html#common-attributes

    Args:
      name: A name for the target
      deps: Exactly one proto_library target to generate Kotlin APIs for
      has_services: Whether to generate code for gRPC services.
      **kwargs: other args to pass to the ultimate kt_jvm_library target
    """
    deps = deps or []

    if len(deps) != 1:
        fail("Expected exactly one dep", "deps")

    kt_jvm_deps = [] + _KT_JVM_PROTO_DEPS

    java_name = name + "_DO_NOT_DEPEND_java_proto"
    java_label = ":" + java_name
    java_proto_library(
        name = java_name,
        deps = deps,
        visibility = ["//visibility:private"],
    )
    kt_jvm_deps.append(java_label)

    if has_services:
        java_grpc_name = name + "_DO_NOT_DEPEND_java_grpc"
        java_grpc_label = ":" + java_grpc_name
        java_grpc_library(
            name = java_grpc_name,
            srcs = deps,
            deps = [java_label],
            visibility = ["//visibility:private"],
        )
        kt_jvm_deps.append(java_grpc_label)
        kt_jvm_deps.append(Label("//imports/io/gprc/kotlin:stub"))

    generated_kt_name = name + "_DO_NOT_DEPEND_generated_kt"
    generated_srcjar = generated_kt_name + ".srcjar"
    _kt_jvm_proto_library_helper(
        name = generated_kt_name,
        proto_dep = deps[0],
        srcjar = generated_srcjar,
        has_services = has_services,
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

def kt_jvm_grpc_proto_library(name, deps, **kwargs):
    """Generates and compiles Java and Kotlin APIs for a gRPC proto_library.

    For standard attributes, see:
      https://docs.bazel.build/versions/master/be/common-definitions.html#common-attributes

    Args:
      name: A name for the target
      deps: Exactly one proto_library target to generate Kotlin APIs for
      **kwargs: other args to pass to the ultimate kt_jvm_library target
    """
    kt_jvm_proto_library(
        name = name,
        deps = deps,
        has_services = True,
        **kwargs
    )
