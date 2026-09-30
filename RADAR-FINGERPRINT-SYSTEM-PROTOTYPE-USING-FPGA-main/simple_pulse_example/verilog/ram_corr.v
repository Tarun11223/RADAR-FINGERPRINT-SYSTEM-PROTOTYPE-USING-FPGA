// ============================================================================
// Module Name  : ram_corr
// Project      : FPGA Radar Matched Filter (Cross-Correlation)
// Target FPGA  : Digilent Nexys A7-100T (Artix-7 XC7A100T-1CSG324C)
// Tool Version : Vivado 2024.x
// Description  : Correlation Results Storage Dual-Port RAM.
//                Stores 16,953 complex correlation result values.
//                Port A: Write interface for Correlator module.
//                Port B: Read interface for Peak Detector & UART Transmitter.
// ============================================================================

`timescale 1ns / 1ps

module ram_corr #(
    parameter DATA_WIDTH = 32,      // 16-bit Real + 16-bit Imag
    parameter ADDR_WIDTH = 15,      // Up to 32,768 depth (16,953 used)
    parameter MAX_DEPTH  = 16953
)(
    input  wire                  clk,
    
    // Port A (Write Port - Correlator Output)
    input  wire                  wea,
    input  wire [ADDR_WIDTH-1:0] addra,
    input  wire [DATA_WIDTH-1:0] dina,
    
    // Port B (Read Port - Peak Search & UART TX)
    input  wire [ADDR_WIDTH-1:0] addrb,
    output reg  [DATA_WIDTH-1:0] doutb
);

    // BRAM Allocation for 16,953 Lags
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] ram [0:MAX_DEPTH-1];

    // Port A Write Operation
    always @(posedge clk) begin
        if (wea && (addra < MAX_DEPTH)) begin
            ram[addra] <= dina;
        end
    end

    // Port B Read Operation (Registered Output - 1 Clock Latency)
    always @(posedge clk) begin
        if (addrb < MAX_DEPTH) begin
            doutb <= ram[addrb];
        end else begin
            doutb <= 32'h00000000;
        end
    end

endmodule
