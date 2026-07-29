#!/usr/bin/env python3
"""Build the GzLevelUp addon package in CI.

Reads these environment variables:
  ADDON_NAME        - addon folder / name (e.g. "GzLevelUp")
  VERSION           - version to stamp, without a leading "v"

Steps:
  1. write VERSION into the addon's .toc (## Version:)
  2. build <ADDON_NAME>-<VERSION>.zip containing the addon folder

On GitHub Actions the resulting zip is attached to the GitHub Release by the
workflow (see .github/workflows/release.yml); this script only produces it.
"""
import os
import shutil

addon = os.environ["ADDON_NAME"]
version = os.environ["VERSION"]
toc_path = os.path.join(addon, addon + ".toc")

# 1) Stamp the version into the .toc
with open(toc_path, encoding="utf-8") as fh:
    lines = fh.readlines()
with open(toc_path, "w", encoding="utf-8") as fh:
    for line in lines:
        if line.startswith("## Version:"):
            line = "## Version: " + version + "\n"
        fh.write(line)
print("Stamped {} -> version {}".format(toc_path, version))

# 2) Build the zip (top-level folder = addon name)
zip_base = "{}-{}".format(addon, version)
shutil.make_archive(zip_base, "zip", ".", addon)
zip_name = zip_base + ".zip"
print("Built {} ({} bytes)".format(zip_name, os.path.getsize(zip_name)))
