#!/usr/bin/env python3
"""Checks what the plugin adds to an app's merged AndroidManifest.xml.

Run after `flutter build appbundle --release` in the example app:

    python3 .github/scripts/merged_manifest_snapshot.py           # check
    python3 .github/scripts/merged_manifest_snapshot.py --update  # rewrite

The plugin's contribution is every manifest element or attribute that the
manifest merger attributes to the plugin module or to a library on its
runtime classpath (Flutter's embedding and its AndroidX dependencies are left
out: every Flutter app has them). The result is compared with
packages/imaji_install_attribution/doc/merged-manifest.snapshot.xml, so a new
permission, query or component from a dependency bump fails CI.
"""

import argparse
import difflib
import glob
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PLUGIN = os.path.join(ROOT, "packages", "imaji_install_attribution")
EXAMPLE = os.path.join(PLUGIN, "example")
SNAPSHOT = os.path.join(PLUGIN, "doc", "merged-manifest.snapshot.xml")
PLUGIN_PROJECT = ":imaji_install_attribution"
ANDROID_NS = "http://schemas.android.com/apk/res/android"

HEADER = """\
<?xml version="1.0" encoding="utf-8"?>
<!--
  What imaji_install_attribution adds to an app's merged AndroidManifest.xml
  in a release build. Generated from the example app by
  .github/scripts/merged_manifest_snapshot.py; CI fails when the build
  differs. Regenerate with that script's update flag after a release build.
  ${applicationId} stands for the host app's application ID.
-->
"""


def fail(message):
    print(f"::error::{message}")
    sys.exit(1)


def plugin_dependencies():
    """group:artifact of every library on the plugin's release runtime
    classpath, except the Flutter embedding and what it pulls in."""
    out = subprocess.run(
        [
            "./gradlew",
            "-q",
            "--console=plain",
            f"{PLUGIN_PROJECT}:dependencies",
            "--configuration",
            "releaseRuntimeClasspath",
        ],
        cwd=os.path.join(EXAMPLE, "android"),
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    deps, skip, seen_root = set(), False, False
    for line in out.splitlines():
        top = re.match(r"^[+\\]--- (\S+)", line)
        if top:
            seen_root = True
            skip = top.group(1).startswith("io.flutter:")
        elif not line.startswith(("|", " ")) or not line.strip():
            continue
        if skip:
            continue
        coord = re.search(r"--- (?:project )?(\S+)", line)
        if coord:
            name = coord.group(1)
            deps.add(name if name.startswith(":") else ":".join(name.split(":")[:2]))
    if not seen_root:
        fail(f"no dependencies listed for {PLUGIN_PROJECT}:\n{out}")
    return deps


def source_of(line):
    """The library a merger report line names, as group:artifact or :project;
    None for the app's own manifest."""
    m = re.search(r"from \[([^\]]+)\]", line)
    if not m:
        return None
    parts = m.group(1).split(":")
    return m.group(1) if m.group(1).startswith(":") else ":".join(parts[:2])


def read_report(path, ours):
    """Node keys and (node key, attribute) pairs that come from `ours`, each
    mapped to the library that added them."""
    nodes, attrs = {}, {}
    node = attr = None
    with open(path, encoding="utf-8") as report:
        for raw in report:
            line = raw.rstrip("\n")
            if not line or line.startswith("--"):
                continue
            if not line.startswith("\t"):
                if re.match(r"^[A-Z]+ from ", line):
                    src = source_of(line)
                    added = line.startswith("ADDED")
                    # A library that only merges into a container (manifest,
                    # application, queries) adds nothing by that alone.
                    if src in ours and (added or "#" in node):
                        nodes.setdefault(node, src)
                else:
                    node, attr = line, None
            elif not line.startswith("\t\t"):
                attr = line.strip()
            else:
                src = source_of(line)
                if src in ours and line.strip().startswith("ADDED"):
                    attrs.setdefault((node, attr), src)
    return nodes, attrs


def qname(name):
    return name.replace("{%s}" % ANDROID_NS, "android:")


def key_of(el):
    """The key the manifest merger prints for an element."""
    if el.tag in ("manifest", "application", "queries", "uses-sdk"):
        return el.tag  # one per manifest, keyed by tag alone
    name = el.get("{%s}name" % ANDROID_NS)
    if name is not None:
        return f"{el.tag}#{name}"
    parts = []
    for child in el:
        for k, v in child.attrib.items():
            parts.append(f"{child.tag}:{qname(k).split(':', 1)[1]}:{v}")
    return f"{el.tag}#{'+'.join(parts)}" if parts else el.tag


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--update", action="store_true", help="rewrite the snapshot")
    args = parser.parse_args()

    build = os.path.join(EXAMPLE, "build", "app")
    report = os.path.join(build, "outputs", "logs", "manifest-merger-release-report.txt")
    manifests = sorted(
        glob.glob(os.path.join(build, "intermediates", "merged_manifest", "release", "*", "AndroidManifest.xml"))
    )
    if not os.path.exists(report) or not manifests:
        fail("no release manifest merge output; run `flutter build appbundle --release` in the example first")

    ours = plugin_dependencies() | {PLUGIN_PROJECT}
    print("Plugin sources:", ", ".join(sorted(ours)))
    tree = ET.parse(manifests[0])
    root = tree.getroot()
    package = root.get("package")
    nodes, attrs = read_report(report, ours)
    # The report prints some keys with ${applicationId} unresolved.
    nodes = {k.replace("${applicationId}", package): v for k, v in nodes.items()}
    attrs = {(k.replace("${applicationId}", package), a): v for (k, a), v in attrs.items()}

    def neutral(value):
        return escape(value.replace(package, "${applicationId}"), {'"': "&quot;"})

    def open_tag(el, keep, depth, close):
        pad = "    " * depth
        items = [(qname(k), neutral(v)) for k, v in el.attrib.items() if qname(k) in keep]
        items.sort(key=lambda kv: (kv[0] != "android:name", kv[0]))
        if not items:
            return [f"{pad}<{el.tag}{close}>"]
        if len(items) == 1:
            k, v = items[0]
            return [f'{pad}<{el.tag} {k}="{v}"{close}>']
        lines = [f"{pad}<{el.tag}"]
        lines += [f'{pad}    {k}="{v}"' for k, v in items]
        lines[-1] += f"{close}>"
        return lines

    covered = set()

    def whole(el, depth):
        covered.add(key_of(el))
        children = list(el)
        keep = {qname(k) for k in el.attrib}
        if not children:
            return open_tag(el, keep, depth, " /")
        lines = open_tag(el, keep, depth, "")
        for child in children:
            lines += whole(child, depth + 1)
        return lines + ["    " * depth + f"</{el.tag}>"]

    def emit(el, depth):
        key = key_of(el)
        if key in nodes and el is not root:
            return ["    " * depth + f"<!-- from {nodes[key]} -->"] + whole(el, depth)
        own = {a for (k, a) in attrs if k == key}
        inner = []
        for child in el:
            inner += emit(child, depth + 1)
        if not own and not inner and el is not root:
            return []
        covered.update((key, a) for a in own)
        keep = set(own)
        if own:
            keep.add("android:name")
        lines = []
        for a in sorted(own):
            lines.append("    " * depth + f"<!-- {a} from {attrs[(key, a)]} -->")
        if el is root:
            extra = "".join(f' {a}="{neutral(el.get(a.replace("android:", "{%s}" % ANDROID_NS)))}"' for a in sorted(own))
            lines.append(f'<manifest xmlns:android="{ANDROID_NS}"{extra}>')
        elif not inner:
            return lines + open_tag(el, keep, depth, " /")
        else:
            lines += open_tag(el, keep, depth, "")
        return lines + inner + ["    " * depth + f"</{el.tag}>"]

    body = emit(root, 0)
    # Fail loudly rather than drop an entry the XML walk did not match.
    missing = [k for k in nodes if k not in covered and k != "manifest"]
    missing += [f"{k} {a}" for (k, a) in attrs if k not in nodes and (k, a) not in covered]
    if missing:
        fail("could not place these merger report entries in the snapshot: " + ", ".join(sorted(missing)))

    actual = HEADER + "\n".join(body) + "\n"
    if args.update:
        with open(SNAPSHOT, "w", encoding="utf-8") as f:
            f.write(actual)
        print(f"Wrote {os.path.relpath(SNAPSHOT, ROOT)}")
        print(actual)
        return
    try:
        with open(SNAPSHOT, encoding="utf-8") as f:
            expected = f.read()
    except FileNotFoundError:
        expected = ""
    if actual != expected:
        rel = os.path.relpath(SNAPSHOT, ROOT)
        sys.stdout.writelines(
            difflib.unified_diff(
                expected.splitlines(True), actual.splitlines(True), rel, "release build"
            )
        )
        fail(
            f"the plugin's merged-manifest contributions differ from {rel}. "
            "If the change is intended, run .github/scripts/merged_manifest_snapshot.py "
            "--update after a release build and commit the snapshot."
        )
    print(actual)
    print("Merged-manifest contributions match the snapshot.")


if __name__ == "__main__":
    main()
