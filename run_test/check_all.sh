#!/usr/bin/env bash
BENCHMARK_DIR="./Benchmarks"

for dir in "$BENCHMARK_DIR"/*/ ; do
    if [ -d "$dir" ]; then
        # Remove trailing slash and get the base name (e.g., "my_design_v2")
        case_name=$(basename "${dir%/}")
        
        # 1. Determine top_module: remove everything from "_v2" onwards
        top_module="${case_name%_v2*}"
        
        # 2. Find the one and only subdirectory inside 'dir'
        # This looks for the first directory inside $dir
        input_dir=$(find "$dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)

        if [ -n "$input_dir" ]; then
            echo "Processing case: $case_name (Module: $top_module)"

            # Step 1: Run the shell script
            bash run_test/run.sh "$input_dir" ./Platform/ASAP7/ ./output_file/${case_name} "$top_module" > "run_test/log/${case_name}.log"

            # Step 2: Run the python equivalence check
            cd equiv_check/
            python3 netlist_equiv_check.py --pre_opt "../$input_dir" --post ../output_file/${case_name} > "log/${case_name}_eq.log"
            cd ..
        else
            echo "Warning: No subdirectory found in $dir, skipping."
        fi
    fi
done