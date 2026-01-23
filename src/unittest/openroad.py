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

