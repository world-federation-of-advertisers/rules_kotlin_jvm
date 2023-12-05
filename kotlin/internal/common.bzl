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

"""Common defs."""

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

def create_srcjar(ctx, zipper, output_jar, *args):
    """Bundles source files into a srcjar.

    Args:
      ctx: rule context
      zipper: zipper executable
      output_jar: output srcjar
      *args: input directories
    """
    input_dirs = args

    zipper_args = ctx.actions.args()
    zipper_args.add("c", output_jar)
    zipper_args.add_all(input_dirs)

    ctx.actions.run(
        outputs = [output_jar],
        inputs = input_dirs,
        executable = zipper,
        arguments = [zipper_args],
        mnemonic = "SrcJar",
        progress_message = "Generating srcjar for " + ctx.label.name,
        toolchain = None,
    )

def merge_srcjars(ctx, zipper, extract_srcjars, output_jar, *args):
    """Merges multiple srcjars into a single srcjar.

    Args:
      ctx: rule context
      zipper: zipper executable
      extract_srcjars: extract_srcjars executable
      output_jar: output srcjar
      *args: input srcjars
    """
    input_jars = args

    tmp_dir_name = ctx.label.name + "_srcjars"
    tmp_dir = ctx.actions.declare_directory(tmp_dir_name)

    merge_args = ctx.actions.args()
    merge_args.add(zipper)
    merge_args.add(tmp_dir.path)
    merge_args.add_all(input_jars)

    ctx.actions.run(
        outputs = [tmp_dir],
        inputs = input_jars,
        executable = extract_srcjars,
        tools = [zipper],
        arguments = [merge_args],
        mnemonic = "ExtractSrcJars",
        toolchain = None,
    )

    create_srcjar(ctx, zipper, output_jar, tmp_dir)
