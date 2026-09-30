// ============================================================================
// Module Name  : fifo
// Project      : FPGA Radar Matched Filter (Cross-Correlation)
// Target FPGA  : Digilent Nexys A7-100T (Artix-7 XC7A100T-1CSG324C)
// Tool Version : Vivado 2024.x / 2025.x
// Description  : Synchronous Rx Buffer & FIFO Module for 19,071 complex IQ
//                samples (32-bit width: 16-bit I + 16-bit Q).
//                Supports synchronous clear signal (clr) to reset write pointer
//                between UART sessions.
// ============================================================================

`timescale 1ns / 1ps

module fifo #(
    parameter DATA_WIDTH = 32,      // 16-bit I + 16-bit Q
    parameter ADDR_WIDTH = 15,      // Up to 32,768 depth (19,071 used)
    parameter MAX_DEPTH  = 19071
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  clr,     // Synchronous pointer clear
    
    // Write Interface (UART Receiver)
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] din,
    output wire                  full,
    output reg  [ADDR_WIDTH-1:0] wr_ptr,
    
    // Read Interface (Correlator Sliding Window)
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output reg  [DATA_WIDTH-1:0] dout,
    
    // Status Interface
    output wire [ADDR_WIDTH-1:0] sample_count
);

    // Block RAM Storage Array for Received Echo Signal
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:MAX_DEPTH-1];

    // Write Pointer Management
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr <= {ADDR_WIDTH{1'b0}};
        end else if (clr) begin
            wr_ptr <= {ADDR_WIDTH{1'b0}};
        end else if (wr_en && (wr_ptr < MAX_DEPTH)) begin
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    // Pure Synchronous BRAM Array Write (No Async Reset for BRAM Inference)
    always @(posedge clk) begin
        if (wr_en && (wr_ptr < MAX_DEPTH)) begin
            mem[wr_ptr] <= din;
        end
    end

    // Read Port Access (Registered Output - 1 Clock Latency)
    always @(posedge clk) begin
        if (rd_addr < MAX_DEPTH) begin
            dout <= mem[rd_addr];
        end else begin
            dout <= {DATA_WIDTH{1'b0}};
        end
    end

    // Status Flags
    assign full         = (wr_ptr >= MAX_DEPTH);
    assign sample_count = wr_ptr;

    initial begin
        wr_ptr = {ADDR_WIDTH{1'b0}};
    end

endmodule
