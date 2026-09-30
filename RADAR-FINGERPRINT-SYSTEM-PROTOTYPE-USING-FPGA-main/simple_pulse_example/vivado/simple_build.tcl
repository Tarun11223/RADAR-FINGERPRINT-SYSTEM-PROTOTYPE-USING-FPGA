# =============================================================================
# TCL Script    : simple_build.tcl
# Project       : Simple Rectangular Pulse Cross-Correlation on FPGA
# Target Device : Digilent Nexys A7-100T (xc7a100tcsg324-1)
# Usage         : vivado -mode batch -source simple_build.tcl
# =============================================================================

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize "$script_dir/.."]

set project_name "simple_cross_correlation"
set project_dir  "$root_dir/vivado_project"

puts "=== Creating Simple Cross-Correlation Vivado Project ==="
puts "Script Directory: $script_dir"
puts "Root Directory  : $root_dir"

# Create project
create_project $project_name $project_dir -part xc7a100tcsg324-1 -force

# Add source files
add_files -norecurse [list \
    "$root_dir/verilog/simple_top.v" \
    "$root_dir/verilog/correlator.v" \
    "$root_dir/verilog/controller.v" \
    "$root_dir/verilog/fifo.v" \
    "$root_dir/verilog/bram_tx.v" \
    "$root_dir/verilog/ram_corr.v" \
    "$root_dir/verilog/peak_detector.v" \
    "$root_dir/verilog/uart_rx.v" \
    "$root_dir/verilog/uart_tx.v" \
]

# Add memory init file
add_files -norecurse "$root_dir/data/simple_tx.mem"

# Add constraints
add_files -fileset constrs_1 -norecurse "$root_dir/vivado/simple_constraints.xdc"

# Set simple_top as top module
set_property top simple_top [current_fileset]
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
# Run Implementation (Place & Route)
# -----------------------------------------------------------------------
puts "\n=== Launching Implementation ==="
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed!"
    exit 1
}
puts "=== BITSTREAM GENERATION COMPLETE ==="
puts "=== Bitstream: $project_dir/$project_name.runs/impl_1/simple_top.bit ==="
exit
