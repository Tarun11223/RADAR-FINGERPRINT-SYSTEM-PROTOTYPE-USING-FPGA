# =============================================================================
# TCL Script    : simple_program.tcl
# Project       : Simple Rectangular Pulse Auto-Programmer
# Usage         : vivado -mode batch -source simple_program.tcl
# =============================================================================

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize "$script_dir/.."]

set bit_file "$root_dir/vivado_project/simple_cross_correlation.runs/impl_1/simple_top.bit"

if {![file exists $bit_file]} {
    puts "ERROR: Could not find bitstream file at $bit_file"
    puts "Please run simple_build.tcl first to synthesize and generate simple_top.bit."
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

puts "=== SIMPLE CROSS-CORRELATION FPGA PROGRAMMED SUCCESSFULLY ==="
puts "=== Bitstream : $bit_file"
puts "=== LED2 ON   : FPGA is in STATE_WAIT_RX — Ready for MATLAB ==="

close_hw_target
disconnect_hw_server
close_hw_manager
exit
