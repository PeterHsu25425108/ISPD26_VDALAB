# =========================================================
# 0. 接收參數與設定
# =========================================================
# OpenROAD 自動把後面的參數放進 $argv 列表
# 所以我們用 lindex (list index) 來取值

set top_module      $::env(TOP_MODULE)
set platform_dir    $::env(PLATFORM_DIR)
set input_dir       $::env(INPUT_DIR)
set output_dir      $::env(OUTPUT_DIR)



# =========================================================
# 1. 讀取技術檔案 (Library Setup)
# =========================================================

puts "Loading Libraries..."

# 1.1 讀取 Tech LEF
read_lef "${platform_dir}/lef/asap7_tech_1x_201209.lef"

# 1.2 讀取 Standard-cell LEF (處理 *)
# glob 會抓取所有符合條件的檔案路徑
foreach lef_file [glob -nocomplain "${platform_dir}/lef/asap7sc7p5t_28_*_1x_220121a.lef"] {
    puts "Reading LEF: $lef_file"
    read_lef $lef_file
}

foreach lef_file [glob -nocomplain "${platform_dir}/lef/fakeram_256x64.lef"] {
    puts "Reading LEF: $lef_file"
    read_lef $lef_file
}

# 1.3 讀取 Macro LEF (處理 *)
foreach lef_file [glob -nocomplain "${platform_dir}/lef/sram_asap7_*.lef"] {
    puts "Reading LEF: $lef_file"
    read_lef $lef_file
}

# 1.4 讀取 LIB Files (處理 *)
foreach lib_file [glob -nocomplain "${platform_dir}/lib/*.lib"] {
    puts "Reading LIB: $lib_file"
    read_liberty $lib_file
}

# =========================================================
# 2. 讀取設計 (Design Loading)
# =========================================================

puts "Loading Design..."

puts "Design dir = $input_dir"


read_verilog "$input_dir/contest.v"


read_def     "$input_dir/contest.def"

read_sdc     "$input_dir/contest.sdc"
# =========================================================
# 3. 執行 ECO 並產生 Changelist
# =========================================================

# 1.5 設定 RC 參數
source "${platform_dir}/util/setRC.tcl"
puts "Starting ECO process..."
# 定義一個 Helper 函數，用來同時「修改電路」並「寫入 changelist」
# 2. 修 DRV (Slew/Cap) -> 物理實現基礎
repair_design
#
## 3. 修 Setup -> 效能優化
repair_timing -setup -skip_gate_cloning -skip_pin_swap 
#
## 4. 重要！重新合法化擺放 (把重疊的、沒對齊的解掉)
detailed_placement
# --- [你的 ECO 策略寫在這裡] ---

# puts "\n\[Eviction Protocol\] Starting scan for illegal placement..."

# # 建議用 ord::get_db_block，ORFS/常見腳本都這樣拿 dbBlock
# set block [ord::get_db_block]

# # all instances
# set insts [$block getInsts]

# # 1) 建立 Blockage 清單：getBlockages 取到的是 placement blockages (dbBlockage)
# #    你 DEF 是 PLACEMENT + SOFT RECT，所以不用 getType 篩
# set danger_zones {}
# foreach b [$block getBlockages] {
#     set r [$b getBBox]
#     # 存成純座標，避免後面 $zone xMax 這種物件呼叫出問題
#     lappend danger_zones [list [$r xMin] [$r yMin] [$r xMax] [$r yMax]]
# }
# set zone_count [llength $danger_zones]

# puts "\[Eviction Protocol\] Loaded $zone_count Placement Blockage Zones."

# if { $zone_count > 0 } {
#     lassign [lindex $danger_zones 0] x1 y1 x2 y2
#     puts "   -> First Zone: ( $x1 $y1 ) - ( $x2 $y2 )"
# } else {
#     puts "\[ERROR\] Still finding 0 blockages! Please check if 'read_def' was successful."
# }

# # 2) 遍歷所有 Instance，把誤闖禁區的踢出去
# set kicked_count 0

# foreach inst $insts {
#     # 忽略 Fixed (Macro/IO) 和已經 Unplaced 的
#     if { [$inst isFixed] } { continue }
#     set st [$inst getPlacementStatus]
#     if { $st eq "UNPLACED" } { continue }

#     set master_name [[$inst getMaster] getName]

#     # Buffer/Inverter 合法，不踢
#     if { [regexp -nocase {BUF|INV|DLY|repeater} $master_name] } {
#         continue
#     }

#     set ibox [$inst getBBox]
#     set ix1 [$ibox xMin]; set iy1 [$ibox yMin]
#     set ix2 [$ibox xMax]; set iy2 [$ibox yMax]

#     foreach zone $danger_zones {
#         lassign $zone zx1 zy1 zx2 zy2

#         # overlap: not (separated)
#         if { !($ix1 >= $zx2 || $ix2 <= $zx1 || $iy1 >= $zy2 || $iy2 <= $zy1) } {
#             $inst setPlacementStatus UNPLACED
#             incr kicked_count
#             break
#         }
#     }
# }

# puts "\[Eviction Protocol\] Kicked $kicked_count illegal logic cells."

# # 3) 重新放置：UNPLACED 通常要靠 global_placement 才會再被放回去
# if { $kicked_count > 0 } {
#     puts "\[Eviction Protocol\] Re-running incremental global_placement + detailed_placement..."
#     if { [catch {global_placement -incremental} err] } {
#         puts "\[WARNING\] global_placement error: $err"
#     }
#     if { [catch {detailed_placement} err] } {
#         puts "\[WARNING\] detailed_placement error: $err"
#     } else {
#         puts "\[SUCCESS\] Placement updated."
#     }
# }


# 4. 最後再檢查一次
check_placement -verbose

# 範例：
# eco_resize "u_dct/u_quant/inst_123" "BUF_X4"
# eco_resize "u_jpeg/inst_456" "AND2_X2"

# 如果你是用 Python 產生的指令，請用 source 匯入
# source "my_eco_algorithm_output.tcl"

# -----------------------------


# =========================================================
# 4. 輸出結果 (Outputs)
# =========================================================

puts "Writing final files to $output_dir ..."

# 確保輸出檔名符合比賽要求 (contest.def / contest.v)
write_def "${output_dir}/contest.def"
write_verilog "${output_dir}/contest.v"

# Source the utility functions
source equiv_check/or_utils.tcl
# Write out the node and net files
write_node_and_net_files "${output_dir}/node.csv" "${output_dir}/nets.csv"

puts "Done!"
