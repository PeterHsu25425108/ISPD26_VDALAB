set design_name     "$::env(DESIGN_NAME)"
set folder          "$::env(FOLDER_NAME)"
set log_dir         "$::env(LOG_DIR)"
set top_proj_dir    "$::env(TOP_PROJ_DIR)"
set proj_dir        "$::env(PROJ_DIR)"
set lib_setup_file    "$::env(LIB_SETUP)"
set design_setup_file "$::env(DESIGN_SETUP)"
set or_utils_file     "$::env(OR_UTILS)"

source $lib_setup_file
source $design_setup_file
source $or_utils_file

## Read lef and lib files
foreach lef_file ${lefs}    { read_lef     $lef_file }
foreach lib_file ${libbest} { read_liberty $lib_file }

## Read the design
read_def ${def_file}
read_sdc ${sdc_file}

source $rc_file

set node_file ${log_dir}/node.csv
set net_file ${log_dir}/nets.csv

write_node_and_net_files $node_file $net_file

puts "Script completed successfully"


