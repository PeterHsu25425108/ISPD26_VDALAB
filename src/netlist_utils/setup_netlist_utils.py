"""
setup_netlist_utils.py
Build script for the netlist_utils C++/pybind11 extension.

Usage (from the ISPD26_VDALAB root):
    python3 src/netlist_utils/setup_netlist_utils.py

The compiled .so is placed in src/netlist_utils/ and imported via:
    sys.path.insert(0, os.path.join(src_dir, 'netlist_utils'))
    import netlist_utils
"""

import os
import sys
from setuptools import setup, Extension

import pybind11

# Locate the this file's directory (= src/) to place the .so there
HERE = os.path.dirname(os.path.abspath(__file__))

ext = Extension(
    name="netlist_utils",
    sources=[os.path.join(HERE, "netlist_utils.cpp")],
    include_dirs=[
        pybind11.get_include(),          # pybind11 headers
        "/usr/include/python3.12",       # CPython headers
    ],
    language="c++",
    extra_compile_args=[
        "-std=c++17",
        "-O3",
        "-march=native",
        "-fvisibility=hidden",   # required for pybind11 shared libs
        "-Wall",
        "-Wno-unused-variable",
    ],
    extra_link_args=["-Wl,-rpath,$ORIGIN"],
)

setup(
    name="netlist_utils",
    version="1.0.0",
    description="C++/pybind11 acceleration for netlist traversal",
    ext_modules=[ext],
    # Place the .so in src/ so imports work without path manipulation
    script_args=["build_ext", f"--build-lib={HERE}", "--inplace"],
)
