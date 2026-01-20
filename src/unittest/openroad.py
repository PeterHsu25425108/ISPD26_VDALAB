#!/usr/bin/env python3
import json
import openroad as ord
from openroad import Tech, Design, Timing
import os
from pathlib import Path
import sys
import glob
from glob import glob

# "Usage: $0 run.sh <input_dir> <platform_dir> <output_dir> <top_module>"
# add the 3 arguments

input_dir = sys.argv[1]
platform_dir = sys.argv[2]
output_dir = sys.argv[3]
top_module = sys.argv[4]

# Find the lef. lib, util directories inside platform_dir
lef_dir = Path(platform_dir) / "lef"
lib_dir = Path(platform_dir) / "lib"
util_dir = Path(platform_dir) / "util"

lefFiles = lef_dir.glob("*.lef")
libFiles = lib_dir.glob("*.lib")

tech = Tech()


# read technology files
for lef in lefFiles:
    print("Lef path: ", str(lef))
    tech.readLef(str(lef))
    print("Read lef: ", str(lef))
for lib in libFiles:
    print("Lib path: ", str(lib))
    tech.readLiberty(str(lib))
    print("Read lib: ", str(lib))

# read desgin files
design = Design(tech)
# print("Def path: ", f"{input_dir}/contest.def")
# design.readDef(f"{input_dir}/contest.def")
# print("Read def")
design.readVerilog(f"{input_dir}/contest.v")
print("Read verilog")
design.link(top_module)

# design.evalTclString(f"read_verilog {input_dir}/contest.v")
# print("Read verilog")
# design.evalTclString(f"read_def {input_dir}/contest.def")
# print("Read def")

sdcFile = f"{input_dir}/contest.sdc"
design.evalTclString("read_sdc %s"%sdcFile)
print("Read SDC")

rcFile = f"{util_dir}/setRC.tcl"
# design.evalTclString("set rc_file %s"%rcFile)
design.evalTclString(f"source {rcFile}")
print("Read rc")

design.evalTclString("set_cmd_units -time ns -capacitance pF -current mA -voltage V -resistance kOhm -distance um -power mW")
design.evalTclString("set_units -power mW")

timing = Timing(design)
insts = design.getBlock().getInsts()[:-10]

sta = tech.getSta()
# sta.findTiming()

design.evalTclString(f"report_worst_slack")
# get the reported wns value
wns_str = design.evalTclString("worst_slack -max")
wns = float(wns_str)
print("WNS: ", wns)

# report wns path, the max slack is wns
design.evalTclString(f"report_checks -path_delay max -format json -group_path_count 10 -unique_paths_to_endpoint -slack_max {wns * 0.6} -slack_min {wns} > tmp.json")
with open("tmp.json", "r") as f:
    path_report = json.load(f)
# os.remove("tmp.json")

print("processing path report...")
# print path report
outstr = ""
for path in path_report["checks"]:
    outstr += f"Path slack: {path['slack']}\n"
    outstr += "  From:\n"
    for point in path["source_path"]:
        outstr += f"    {point}\n"
    outstr += "\n"
    
print("Path report:")
print(outstr)

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
#     print(f"Inst: {inst.getName()}, Pin: {pin_name}, Rise Arrival: {pin_rise_arr}, Fall Arrival: {pin_fall_arr}, Rise Slack: {pin_rise_slack}, Fall Slack: {pin_fall_slack}, Slew: {pin_slew}")

# wns max -53354.20