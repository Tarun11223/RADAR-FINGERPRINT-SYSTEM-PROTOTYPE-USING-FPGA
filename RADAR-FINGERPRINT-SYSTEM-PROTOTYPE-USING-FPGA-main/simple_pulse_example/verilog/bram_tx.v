// ============================================================================
// Module Name  : bram_tx
// Project      : FPGA Radar Matched Filter (Cross-Correlation)
// Target FPGA  : Digilent Nexys A7-100T (Artix-7 XC7A100T-1CSG324C)
// Tool Version : Vivado 2024.x / 2025.x
// Description  : Dual-Port Block RAM storing 2119 Transmit LFM Chirp complex
//                samples (Q1.15 format). Initialized via "tx.mem".
//                Port A: Write interface (optional dynamic loading/re-config).
//                Port B: Read interface for Sequential MAC Correlator.
// ============================================================================

`timescale 1ns / 1ps

module bram_tx #(
    parameter DATA_WIDTH = 32,      // 16-bit Real (I) + 16-bit Imag (Q)
    parameter ADDR_WIDTH = 12,      // Up to 4096 depth (2119 used)
    parameter MEM_DEPTH  = 2119,
    parameter INIT_FILE  = "E:/xilinxprojects/radar_cross_corelation/tx.mem"
)(
    input  wire                  clk,
    
    // Port A (Write / Control Interface)
    input  wire                  wea,
    input  wire [ADDR_WIDTH-1:0] addra,
    input  wire [DATA_WIDTH-1:0] dina,
    output reg  [DATA_WIDTH-1:0] douta,
    
    // Port B (Read Interface for Correlator)
    input  wire [ADDR_WIDTH-1:0] addrb,
    output reg  [DATA_WIDTH-1:0] doutb
);

    // BRAM Array Allocation
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] ram [0:MEM_DEPTH-1];

    // BRAM Initialization from Hex File
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, ram);
        end
    end

    // Port A Read/Write Operation
    always @(posedge clk) begin
        if (wea) begin
            ram[addra] <= dina;
            douta      <= dina;
        end else begin
            douta      <= ram[addra];
        end
    end

    // Port B Read Operation (1 Clock Cycle Latency)
    always @(posedge clk) begin
        doutb <= ram[addrb];
    end

endmodule
