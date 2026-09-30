# =============================================================================
# TCL Script    : program.tcl
# Project       : FPGA Radar Matched Filter Auto-Programmer
# Usage         : vivado -mode batch -source program.tcl
# =============================================================================

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize "$script_dir/.."]

set bit_file "$root_dir/vivado_project/radar_cross_corelation.runs/impl_1/top.bit"

if {![file exists $bit_file]} {
    puts "ERROR: Could not find bitstream file at $bit_file"
    puts "Please run build.tcl first to synthesize and generate top.bit."
    exit 1
}

puts "=== Programming Nexys A7-100T with $bit_file ==="

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set device [lindex [get_hw_devices] 0]
current_hw_device $device
refresh_hw_device -update_hw_probes false $device

set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device
refresh_hw_device $device

puts "=== FPGA BOARD PROGRAMMED SUCCESSFULLY WITH TOP.BIT ==="
puts "=== LED2 ON : System in STATE_WAIT_RX — Ready for MATLAB ==="

close_hw_target
disconnect_hw_server
close_hw_manager
exit
