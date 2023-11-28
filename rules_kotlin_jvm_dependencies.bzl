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

"""Module extension for dependencies of rules_kotlin_jvm."""

load(
    "@bazel_tools//tools/build_defs/repo:http.bzl",
    "http_archive",
)

_archive_version = tag_class(attrs = {
    "version": attr.string(),
    "sha256": attr.string(),
})

RepoArchiveInfo = provider(
    "Repository archive",
    fields = {
        "name": "Repository name",
        "url_templates": "List of templates of URLs that can be filled in with a version",
        "prefix_template": "Template of prefix to strip from archive",
    },
)

ArchiveVersionInfo = provider(
    "Archive version",
    fields = {
        "version": "Version of the archive",
        "sha256": "SHA-256 sum of the archive",
    },
)

def _format_url_templates(repo_archive, version):
    """Returns URL templates with version substituted."""
    return [
        template.format(version = version)
        for template in repo_archive.url_templates
    ]

def _format_prefix(repo_archive, version):
    if not hasattr(repo_archive, "prefix_template"):
        return None
    return repo_archive.prefix_template.format(
        version = version,
    )

def _versioned_http_archive(repo_archive, archive_version):
    http_archive(
        name = repo_archive.name,
        sha256 = archive_version.sha256,
        strip_prefix = _format_prefix(repo_archive, archive_version.version),
        urls = _format_url_templates(repo_archive, archive_version.version),
    )

_GRPC_JAVA = RepoArchiveInfo(
    name = "io_grpc_grpc_java",
    url_templates = [
        "https://github.com/grpc/grpc-java/archive/refs/tags/v{version}.tar.gz",
    ],
    prefix_template = "grpc-java-{version}",
)

def _rules_kotlin_jvm_dependencies_impl(mctx):
    grpc_java_version = None
    for mod in mctx.modules:
        for archive_version in mod.tags.grpc_java_version:
            if grpc_java_version:
                fail("Only one grpc-java version is supported")
            grpc_java_version = ArchiveVersionInfo(version = archive_version.version, sha256 = archive_version.sha256)

    _versioned_http_archive(_GRPC_JAVA, grpc_java_version)

rules_kotlin_jvm_dependencies = module_extension(
    implementation = _rules_kotlin_jvm_dependencies_impl,
    tag_classes = {
        "grpc_java_version": _archive_version,
    },
)
