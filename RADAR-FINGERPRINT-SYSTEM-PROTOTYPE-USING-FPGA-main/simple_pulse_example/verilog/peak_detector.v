// ============================================================================
// Module Name  : peak_detector
// Project      : FPGA Radar Matched Filter (Cross-Correlation)
// Target FPGA  : Digilent Nexys A7-100T (Artix-7 XC7A100T-1CSG324C)
// Tool Version : Vivado 2024.x / 2025.x
// Description  : Real-Time Radar Peak Detector Module.
//                Fully Pipelined DSP architecture for 100 MHz Timing Closure.
//                Scans correlation RAM array [0..16952] to compute magnitude
//                squared |R(k)|^2 = I^2 + Q^2 and locate peak index k_peak.
// ============================================================================

`timescale 1ns / 1ps

module peak_detector #(
    parameter DATA_WIDTH = 32,      // 16-bit Real + 16-bit Imag
    parameter ADDR_WIDTH = 15,      // Address width (16,953 depth)
    parameter MAX_DEPTH  = 16953
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  start_search,
    
    // Memory Interface to Correlation RAM
    output reg  [ADDR_WIDTH-1:0] rd_addr,
    input  wire [DATA_WIDTH-1:0] corr_din,
    
    // Detected Peak Output Signals
    output reg  [ADDR_WIDTH-1:0] peak_index,
    output reg  signed [15:0]    peak_real,
    output reg  signed [15:0]    peak_imag,
    output reg  [47:0]           peak_mag_sq,
    output reg                   peak_found
);

    // FSM States
    localparam STATE_IDLE   = 2'b00;
    localparam STATE_FETCH  = 2'b01;
    localparam STATE_EVAL   = 2'b10;
    localparam STATE_DONE   = 2'b11;

    reg [1:0] state;
    reg [ADDR_WIDTH-1:0] fetch_idx;
    reg [2:0]            drain_cnt;
    reg [ADDR_WIDTH-1:0] rd_addr_d1;

    // Pipeline Registers for 100 MHz Timing Closure
    reg signed [15:0] val_i_r1, val_q_r1;
    reg signed [47:0] sq_i_r2,  sq_q_r2;
    reg [47:0]        mag_sq_r3;

    reg [ADDR_WIDTH-1:0] idx_r1, idx_r2, idx_r3;
    reg signed [15:0]    i_r2, i_r3;
    reg signed [15:0]    q_r2, q_r3;
    reg                  valid_r1, valid_r2, valid_r3;

    // Stage 1, 2, 3 Pipelined Math Core
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_addr_d1 <= 0;
            val_i_r1   <= 16'sd0;
            val_q_r1   <= 16'sd0;
            sq_i_r2    <= 48'sd0;
            sq_q_r2    <= 48'sd0;
            mag_sq_r3  <= 48'd0;
            idx_r1     <= 0;
            idx_r2     <= 0;
            idx_r3     <= 0;
            i_r2       <= 16'sd0;
            i_r3       <= 16'sd0;
            q_r2       <= 16'sd0;
            q_r3       <= 16'sd0;
            valid_r1   <= 1'b0;
            valid_r2   <= 1'b0;
            valid_r3   <= 1'b0;
        end else begin
            rd_addr_d1 <= rd_addr;

            // Stage 1: Sample RAM Output
            val_i_r1 <= $signed(corr_din[31:16]);
            val_q_r1 <= $signed(corr_din[15:0]);
            idx_r1   <= rd_addr_d1;
            valid_r1 <= (state == STATE_EVAL);

            // Stage 2: Register DSP Multipliers (I^2, Q^2)
            sq_i_r2  <= $signed(val_i_r1) * $signed(val_i_r1);
            sq_q_r2  <= $signed(val_q_r1) * $signed(val_q_r1);
            idx_r2   <= idx_r1;
            i_r2     <= val_i_r1;
            q_r2     <= val_q_r1;
            valid_r2 <= valid_r1;

            // Stage 3: Register Addition (I^2 + Q^2)
            mag_sq_r3 <= sq_i_r2 + sq_q_r2;
            idx_r3    <= idx_r2;
            i_r3      <= i_r2;
            q_r3      <= q_r2;
            valid_r3  <= valid_r2;
        end
    end

    // Stage 4: Peak Comparator & FSM
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= STATE_IDLE;
            rd_addr     <= 0;
            fetch_idx   <= 0;
            drain_cnt   <= 0;
            peak_index  <= 0;
            peak_real   <= 16'sd0;
            peak_imag   <= 16'sd0;
            peak_mag_sq <= 48'd0;
            peak_found  <= 1'b0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    peak_found <= 1'b0;
                    if (start_search) begin
                        rd_addr     <= 0;
                        fetch_idx   <= 0;
                        drain_cnt   <= 0;
                        peak_mag_sq <= 48'd0;
                        state       <= STATE_FETCH;
                    end
                end

                STATE_FETCH: begin
                    rd_addr   <= 0;
                    fetch_idx <= 1'b1;
                    state     <= STATE_EVAL;
                end

                STATE_EVAL: begin
                    // Peak Comparison on Pipelined Result
                    if (valid_r3 && (mag_sq_r3 > peak_mag_sq)) begin
                        peak_mag_sq <= mag_sq_r3;
                        peak_index  <= idx_r3;
                        peak_real   <= i_r3;
                        peak_imag   <= q_r3;
                    end

                    if (fetch_idx < MAX_DEPTH) begin
                        rd_addr   <= fetch_idx;
                        fetch_idx <= fetch_idx + 1'b1;
                    end else begin
                        if (drain_cnt < 3'd4) begin
                            drain_cnt <= drain_cnt + 1'b1;
                        end else begin
                            peak_found <= 1'b1;
                            state      <= STATE_DONE;
                        end
                    end
                end

                STATE_DONE: begin
                    peak_found <= 1'b1;
                    if (!start_search) begin
                        state <= STATE_IDLE;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
