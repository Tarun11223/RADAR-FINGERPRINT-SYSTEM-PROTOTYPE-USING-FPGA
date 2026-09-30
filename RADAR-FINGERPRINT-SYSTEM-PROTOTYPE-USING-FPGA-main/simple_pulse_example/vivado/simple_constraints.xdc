## ============================================================================
## File Name    : simple_constraints.xdc
## Project      : Simple Rectangular Pulse Cross-Correlation on FPGA
## Target Board : Digilent Nexys A7-100T (Artix-7 XC7A100T-1CSG324C)
## Tool Version : Vivado 2024.x / 2025.x
## Description  : Physical Pin Mapping & Timing Constraints for simple demo.
##
##                Signal sizes for this project:
##                  peak_index     = 9-bit  (ADDR_CORR=9,  max value=250)
##                  rx_sample_count = 11-bit (ADDR_RX=11,  max value=1500)
##                  state_out      = 4-bit
##
##                NOTE: Cannot reuse constraints.xdc from main radar project
##                because ILA probe widths differ (15-bit vs 9/11-bit here).
## ============================================================================

## ---------------------------------------------------------------------------
## 100 MHz System Clock (Nexys A7 Pin E3)
## ---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports clk]

## ---------------------------------------------------------------------------
## CPU Reset Button (Pin C12 — Active Low)
## ---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN C12 IOSTANDARD LVCMOS33} [get_ports rst_n]

## ---------------------------------------------------------------------------
## USB-UART FTDI Serial Interface (same Nexys A7 FTDI USB pins)
## ---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN C4  IOSTANDARD LVCMOS33} [get_ports uart_rx_i]
set_property -dict {PACKAGE_PIN D4  IOSTANDARD LVCMOS33} [get_ports uart_tx_o]

## ---------------------------------------------------------------------------
## Status LEDs [7:0] — Nexys A7-100T LED0..LED7
## ---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports {led_o[0]}]
set_property -dict {PACKAGE_PIN K15 IOSTANDARD LVCMOS33} [get_ports {led_o[1]}]
set_property -dict {PACKAGE_PIN J13 IOSTANDARD LVCMOS33} [get_ports {led_o[2]}]
set_property -dict {PACKAGE_PIN N14 IOSTANDARD LVCMOS33} [get_ports {led_o[3]}]
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS33} [get_ports {led_o[4]}]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports {led_o[5]}]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports {led_o[6]}]
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports {led_o[7]}]

## ---------------------------------------------------------------------------
## Bitstream Configuration
## ---------------------------------------------------------------------------
set_property BITSTREAM.GENERAL.COMPRESS TRUE  [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33   [current_design]
set_property CONFIG_VOLTAGE 3.3               [current_design]
set_property CFGBVS VCCO                      [current_design]

## ---------------------------------------------------------------------------
## ILA Debug Core — Probing key internal nets (widths match simple_top.v)
##
## Probed signals:
##   probe0 : peak_index      [8:0]   (9-bit,  ADDR_CORR=9)
##   probe1 : rx_sample_count [10:0]  (11-bit, ADDR_RX=11)
##   probe2 : state_out       [3:0]   (4-bit FSM state)
##   probe3 : corr_done       (1-bit)
##   probe4 : uart_rx_i       (1-bit, UART input raw)
##   probe5 : uart_tx_o       (1-bit, UART output raw)
##   probe6 : rx_sample_valid (1-bit)
## ---------------------------------------------------------------------------
create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU      true  [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT  1     [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER          false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH           8192  [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL         false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES    0     [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN            false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN           false [get_debug_cores u_ila_0]

## ILA Clock
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list clk_IBUF_BUFG]]

## probe0 : peak_index [8:0]  (9-bit — ADDR_CORR=9, max=250=0x0FA)
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 9 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list \
    {peak_index[0]} {peak_index[1]} {peak_index[2]} {peak_index[3]} \
    {peak_index[4]} {peak_index[5]} {peak_index[6]} {peak_index[7]} \
    {peak_index[8]} \
]]

## probe1 : rx_sample_count [10:0]  (11-bit — ADDR_RX=11, max=1500)
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 11 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list \
    {rx_sample_count[0]}  {rx_sample_count[1]}  {rx_sample_count[2]} \
    {rx_sample_count[3]}  {rx_sample_count[4]}  {rx_sample_count[5]} \
    {rx_sample_count[6]}  {rx_sample_count[7]}  {rx_sample_count[8]} \
    {rx_sample_count[9]}  {rx_sample_count[10]} \
]]

## probe2 : state_out [3:0]  (4-bit FSM state)
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 4 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list \
    {state_out[0]} {state_out[1]} {state_out[2]} {state_out[3]} \
]]

## probe3 : corr_done (1-bit)
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 1 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list corr_done]]

## probe4 : uart_rx_i (1-bit raw UART input from PC)
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 1 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list uart_rx_i_IBUF]]

## probe5 : uart_tx_o (1-bit raw UART output to PC)
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 1 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list uart_tx_o_OBUF]]

## probe6 : rx_sample_valid (1-bit — pulses for each received sample)
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe6]
set_property port_width 1 [get_debug_ports u_ila_0/probe6]
connect_debug_port u_ila_0/probe6 [get_nets [list rx_sample_valid]]

set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false     [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1            [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_IBUF_BUFG]
