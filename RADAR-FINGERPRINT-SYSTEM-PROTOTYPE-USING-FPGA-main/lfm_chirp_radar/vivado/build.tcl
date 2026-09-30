# =============================================================================
# TCL Script    : build.tcl
# Project       : FPGA Radar Matched Filter (LFM Chirp 19k Rx / 2.1k Tx)
# Target Device : Digilent Nexys A7-100T (xc7a100tcsg324-1)
# Usage         : vivado -mode batch -source build.tcl
# =============================================================================

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize "$script_dir/.."]

set project_name "radar_cross_corelation"
set project_dir  "$root_dir/vivado_project"

puts "=== Creating LFM Chirp Radar Matched Filter Vivado Project ==="
puts "Script Directory: $script_dir"
puts "Root Directory  : $root_dir"

# Create project
create_project $project_name $project_dir -part xc7a100tcsg324-1 -force

# Add Verilog HDL source files
add_files -norecurse [list \
    "$root_dir/verilog/top.v" \
    "$root_dir/verilog/correlator.v" \
    "$root_dir/verilog/controller.v" \
    "$root_dir/verilog/fifo.v" \
    "$root_dir/verilog/bram_tx.v" \
    "$root_dir/verilog/ram_corr.v" \
    "$root_dir/verilog/peak_detector.v" \
    "$root_dir/verilog/uart_rx.v" \
    "$root_dir/verilog/uart_tx.v" \
]

# Add memory initialization file
add_files -norecurse "$root_dir/data/tx.mem"

# Add constraints file
add_files -fileset constrs_1 -norecurse "$root_dir/vivado/constraints.xdc"

# Set top module
set_property top top [current_fileset]
update_compile_order -fileset sources_1

# -----------------------------------------------------------------------
# Run Synthesis
# -----------------------------------------------------------------------
puts "\n=== Launching Synthesis ==="
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}
puts "=== Synthesis Complete ==="

# -----------------------------------------------------------------------
# Run Implementation & Write Bitstream
# -----------------------------------------------------------------------
puts "\n=== Launching Implementation & Bitstream Generation ==="
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed!"
    exit 1
}
puts "=== BITSTREAM GENERATION COMPLETE ==="
puts "Bitstream file: $project_dir/$project_name.runs/impl_1/top.bit"
exit
