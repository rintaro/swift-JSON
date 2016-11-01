#!/usr/bin/env python

import os
import shutil
import subprocess
import tempfile


def copy(src, dst):
    print("copying: " + src + " -> " + dst)
    if os.path.isdir(src):
        if os.path.exists(dst):
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
    else:
        if os.path.exists(dst):
            os.remove(dst)
        shutil.copy(src, dst)


script_dir = os.path.abspath(os.path.dirname(__file__))
old_cwd = os.getcwd()
tmpdir = tempfile.mkdtemp()
os.chdir(tmpdir)

subprocess.call(["git", "clone", "https://github.com/nst/JSONTestSuite.git"])
repo_dir = os.path.join(tmpdir, "JSONTestSuite")

copy(os.path.join(repo_dir, "test_parsing"),
     os.path.join(script_dir, "test_parsing"))
copy(os.path.join(repo_dir, "test_transform"),
     os.path.join(script_dir, "test_transform"))
copy(os.path.join(repo_dir, "README.md"),
     os.path.join(script_dir, "README.md"))
copy(os.path.join(repo_dir, "LICENSE"),
     os.path.join(script_dir, "LICENSE"))

os.chdir(old_cwd)
shutil.rmtree(tmpdir)
