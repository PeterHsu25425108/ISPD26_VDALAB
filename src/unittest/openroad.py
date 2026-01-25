#!/usr/bin/env python3
import json
import openroad as ord
from openroad import Tech, Design, Timing
import os
from pathlib import Path
import sys
import glob
from glob import glob

# Usage: 
# openroad -exit(add this flag to terminate the python shell after running the script) -python {The relative directory to src/unittest}/openroad.py <input_dir> <platform_dir> <output_dir> <top_module>

input_dir = sys.argv[1]
platform_dir = sys.argv[2]
output_dir = sys.argv[3]
top_module = sys.argv[4]

# Find the lef. lib, util directories inside platform_dir
# Expected structure:
# platform_dir/
#    lef/ (all lef files, including tech lef and design lefs)
#    lib/ (all liberty files)
#    util/setRC.tcl
lef_dir = Path(platform_dir) / "lef"
lib_dir = Path(platform_dir) / "lib"
util_dir = Path(platform_dir) / "util"

lefFiles = lef_dir.glob("*.lef")
libFiles = lib_dir.glob("*.lib")

# create tech object, this is for building technology database
tech = Tech()

# read technology files 

# (The techlef file is included in Platform/ASAP7/lef along with the designs' lef files, so we read all the lef files in the lef directory)
for lef in lefFiles:
    print("Lef path: ", str(lef))
    tech.readLef(str(lef))
    print("Read lef: ", str(lef))

# read liberty files    
for lib in libFiles:
    print("Lib path: ", str(lib))
    tech.readLiberty(str(lib))
    print("Read lib: ", str(lib))

# read desgin files
# Expected design files in input_dir:
#    contest.v
#    contest.def
#    contest.sdc
design = Design(tech)

# There are 2 methods available to read in design files: using python API or using evalTclString
# 1. Using python API(readVerilog, readDef)
# Call either of readVerilog or readDef, do not call both, or it will cause error.

# print("Def path: ", f"{input_dir}/contest.def")
# design.readDef(f"{input_dir}/contest.def")
# print("Read def")
design.readVerilog(f"{input_dir}/contest.v")
print("Read verilog")
design.link(top_module)

# 2. Using evalTclString, this function can call any tcl command supported by OpenROAD, and 
#   you can perform read_verilog and read_def just like in tcl script.
# Uncomment the following lines to use evalTclString to read in design files

# design.evalTclString(f"read_verilog {input_dir}/contest.v")
# print("Read verilog")
# design.evalTclString(f"read_def {input_dir}/contest.def")
# print("Read def")

# read sdc file
sdcFile = f"{input_dir}/contest.sdc"
design.evalTclString("read_sdc %s"%sdcFile)
print("Read SDC")

# read rc file
rcFile = f"{util_dir}/setRC.tcl"
# design.evalTclString("set rc_file %s"%rcFile)
design.evalTclString(f"source {rcFile}")
print("Read rc")

# set units
design.evalTclString("set_cmd_units -time ns -capacitance pF -current mA -voltage V -resistance kOhm -distance um -power mW")
design.evalTclString("set_units -power mW")

# Dependency: tech -> design -> timing
timing = Timing(design)

# ============================================================================
# SUBGRAPH CONSTRUCTION FROM WORST SLACK PATH
# ============================================================================
# This section constructs a subgraph containing:
# - Set W: All instances on the design's worst slack path
# - Set D: All instances driven by instances in W (fanout cone)
# The subgraph = W ∪ D
# ============================================================================

# Get worst slack and report it
wns = float(design.evalTclString("worst_slack -max"))
print(f"\nWorst Negative Slack: {wns}")

# Use report_checks to get path details  
design.evalTclString(f"report_checks -path_delay max -format full_clock_expanded -endpoint_path_count 1 > /tmp/worst_path.txt")

# Parse the path report to extract instance names
W_inst_names = set()
try:
    with open("/tmp/worst_path.txt", "r") as f:
        lines = f.readlines()
        in_path_section = False
        for line in lines:
            stripped = line.strip()
            
            # Identify path section
            if 'Delay' in line and 'Time' in line and 'Description' in line:
                in_path_section = True
                continue
            if stripped.startswith('----') and in_path_section:
                continue
            if 'slack' in stripped.lower():
                in_path_section = False
                continue
            
            if in_path_section and stripped:
                # Lines with timing info have format: "delay time ^ inst/pin (cell)"
                # We need to extract instance name from "inst/pin"
                if '(' in line and ')' in line:
                    # Find the part before opening parenthesis
                    parts = line.split('(')
                    if len(parts) >= 2:
                        before_paren = parts[0].strip()
                        # The last token should be "instance/pin" or just "pin"
                        tokens = before_paren.split()
                        if len(tokens) >= 1:
                            pin_path = tokens[-1]  # Last token is the pin path
                            # Extract instance name (everything before the last "/")
                            if '/' in pin_path:
                                inst_name = '/'.join(pin_path.split('/')[:-1])
                                if inst_name and inst_name not in ['input', 'output']:
                                    W_inst_names.add(inst_name)
                        
except Exception as e:
    print(f"Error parsing path report: {e}")
    import traceback
    traceback.print_exc()

print(f"\nParsed {len(W_inst_names)} unique instance names from path report")

# Convert names to instance objects
W = set()
block = design.getBlock()
not_found = []
for name in W_inst_names:
    # Try direct lookup
    inst = block.findInst(name)
    if inst:
        W.add(inst)
    else:
        # Try with backslash escaping
        escaped_name = name.replace('/', '\\/')
        inst = block.findInst(escaped_name)
        if inst:
            W.add(inst)
        else:
            not_found.append(name)

if not_found:
    print(f"Warning: {len(not_found)} instances not found in design")
    print(f"Sample not found: {not_found[:5]}")

print(f"\nSet W has {len(W)} instances on worst path:")
for inst in sorted(list(W), key=lambda x: x.getName())[:20]:
    print(f"  {inst.getName()}")
if len(W) > 20:
    print(f"  ... and {len(W) - 20} more")

# Find instances driven by W (fanout)
driven_insts = set()

for inst in W:
    # Get all output pins of the instance
    for iterm in inst.getITerms():
        if iterm.isOutputSignal():
            # Get the net connected to this output
            net = iterm.getNet()
            if net is not None:
                # Get all iterms connected to this net
                for connected_iterm in net.getITerms():
                    if connected_iterm.isInputSignal():
                        driven_inst = connected_iterm.getInst()
                        if driven_inst not in W:  # Don't include instances already in W
                            driven_insts.add(driven_inst)

print(f"\nInstances driven by W: {len(driven_insts)}")

# Combine to get full subgraph
subgraph_insts = W.union(driven_insts)
print(f"Total subgraph instances (W + driven): {len(subgraph_insts)}")

# Print some stats about the subgraph
print("\nSubgraph instances (first 30):")
for i, inst in enumerate(sorted(list(subgraph_insts), key=lambda x: x.getName())[:30]):
    in_W = "on worst path" if inst in W else "driven by W"
    print(f"  {inst.getName()} ({inst.getMaster().getName()}) - {in_W}")
if len(subgraph_insts) > 30:
    print(f"  ... and {len(subgraph_insts) - 30} more")

insts = design.getBlock().getInsts()[:-10]


# for inst in insts:
#   inst_ITerms = inst.getITerms()
#   for pin in inst_ITerms:
#     if design.isInSupply(pin):
#         continue
#     pin_name = design.getITermName(pin)
#     pin_rise_arr = timing.getPinArrival(pin, timing.Rise)
#     pin_fall_arr = timing.getPinArrival(pin, timing.Fall)
#     pin_rise_slack = timing.getPinSlack(pin, timing.Rise, timing.Max)
#     pin_fall_slack = timing.getPinSlack(pin, timing.Fall, timing.Max)
#     pin_slew = timing.getPinSlew(pin)

