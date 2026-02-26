#!/usr/bin/env bash

# This script is written to reduce the effort for running run.sh
# and enable tighter integration with the official evaluation scripts.

# Usage: ./dev_run.sh [design_name]
# Example: ./dev_run.sh ariane_v2
# If no design_name is provided, all cases in Benchmarks/ will be run.

# Expected folder locations:
# 1. This script is to be run under ISPD26_VDALAB repo's home dir.
# 2. Testcase files (contest.v, contest.def, and contest.sdc) are located at ./Benchmarks/{design_name}/{TCP...(the one and only dir inside {design_name})}.
# 3. Resulting {design_name}.v and {design_name}.def will be at output_file/{design_name}/.

umask 000
BENCHMARK_DIR="./Benchmarks"

# Function to process a single case
process_case() {
    local design_name="$1"
    export LOG_FILE="output_file/${design_name}/runtime_msg.log"
    
    # Create log directory if it doesn't exist
    mkdir -p $(dirname "$LOG_FILE")
    
    # Take the substr of design_name before "_v2" to be top_module
    local top_module=${design_name%%_v2*}
    
    # Find the one and only subdir of ./Benchmarks/{design_name}/
    local input_dir=$(find "Benchmarks/${design_name}/" -mindepth 1 -maxdepth 1 -type d)
    
    local platform_dir="Platform/ASAP7/"
    local output_dir="output_file/${design_name}"
    
    if [ -z "$input_dir" ]; then
        echo "Warning: No subdirectory found in Benchmarks/${design_name}/, skipping."
        return
    fi
    
    # print the variables for debugging
    echo "Input Directory: $input_dir"
    echo "Platform Directory: $platform_dir"
    echo "Output Directory: $output_dir"
    echo "Top Module: $top_module"

    echo " ===== Running design: $design_name ====== "
    
    bash run.sh "$input_dir" "$platform_dir" "$output_dir" "$top_module" | tee ${LOG_FILE}
}

# Check if a specific design name is provided
if [ $# -eq 1 ]; then
    design_name="$1"
    if [ -d "${BENCHMARK_DIR}/${design_name}" ]; then
        echo "Running single case: $design_name"
        process_case "$design_name"
    else
        echo "Error: Design '$design_name' not found in $BENCHMARK_DIR"
        exit 1
    fi
else
    # Process all cases
    echo "Running all cases in $BENCHMARK_DIR"
    for dir in "$BENCHMARK_DIR"/*/ ; do
        if [ -d "$dir" ]; then
            design_name=$(basename "${dir%/}")
            echo "Processing case: $design_name"
            process_case "$design_name"
        fi
    done
fi