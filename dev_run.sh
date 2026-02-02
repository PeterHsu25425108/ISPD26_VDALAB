#!/usr/bin/env bash

# This script is written to reduce the effort for running run.sh
# and enable tighter integration with the official evaluation scripts.

# Usage: ./dev_run.sh <design_name>
# Example: ./dev_run.sh ariane_v2

# Expected folder locations:
# 1. This script is to be run under ISPD26-Contest/ repo's home dir.
# 2. Testcase files (contest.v, contest.def, and contest.sdc) are located at ./Benchmarks/{design_name}/{TCP...(the one and only dir inside {design_name})}.
# 3. Resulting {design_name}.v and {design_name}.def will be at output_file/{design_name}/.
# 4. (TO BE ADDED: Regulation for evaluation and equiv_check scripts)


design_name=$1
# Take the substr of design_name before "_v2" to be top_module
top_module=${design_name%%_v2*}

# Find the one and only subdir of ./Benchmarks/{design_name}/
input_dir=$(find "Benchmarks/${design_name}/" -mindepth 1 -maxdepth 1 -type d)

platform_dir="Platform/ASAP7/"
output_dir="output_file/${design_name}"

# print the variables for debugging
echo "Input Directory: $input_dir"
echo "Platform Directory: $platform_dir"
echo "Output Directory: $output_dir"
echo "Top Module: $top_module"

bash run.sh "$input_dir" "$platform_dir" "$output_dir" "$top_module"