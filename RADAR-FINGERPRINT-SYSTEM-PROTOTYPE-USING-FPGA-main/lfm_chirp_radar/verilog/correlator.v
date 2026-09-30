// ============================================================================
// Module Name  : correlator
// Project      : FPGA Radar Matched Filter (Cross-Correlation)
// Target FPGA  : Digilent Nexys A7-100T (Artix-7 XC7A100T-1CSG324C)
// Tool Version : Vivado 2024.x / 2025.x
// Description  : Sequential Complex Matched Filter Correlator.
//                Executes 1 MAC operation per clock cycle for each lag k.
//                Accumulates N_Tx (2119) products per delay to compute R(k).
//                Generates 48-bit signed Real & Imaginary correlation results.
//
// TIMING BUDGET at 100 MHz:
//   - BRAM read latency = 1 cycle
//   - Multiplier pipeline = 2 cycles (Stage1: 4x multiply, Stage2: 2x add)
//   - Accumulate uses valid_d2 (2-cycle delay from en_acc going low)
//   - Drain cycles needed = 3 (1 BRAM + 2 multiply/add) AFTER en_acc goes low
// ============================================================================

`timescale 1ns / 1ps

module correlator #(
    parameter N_TX       = 2119,
    parameter N_RX       = 19071,
    parameter TOTAL_LAGS = 16953,  // N_RX - N_TX + 1
    parameter ADDR_TX    = 12,
    parameter ADDR_RX    = 15,
    parameter ADDR_CORR  = 15
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    
    // Memory Read Data Inputs
    input  wire [31:0] tx_dout,   // {Tx_Real[15:0], Tx_Imag[15:0]}
    input  wire [31:0] rx_dout,   // {Rx_Real[15:0], Rx_Imag[15:0]}
    
    // Memory Addressing Outputs
    output reg  [ADDR_TX-1:0]   tx_addr,
    output reg  [ADDR_RX-1:0]   rx_addr,
    
    // Correlation Output Interface
    output wire                 corr_valid,
    output wire [ADDR_CORR-1:0] corr_lag,
    output wire signed [47:0]   corr_real,
    output wire signed [47:0]   corr_imag,
    output wire                 corr_done
);

    // FSM States
    localparam STATE_IDLE      = 3'b000;
    localparam STATE_FETCH     = 3'b001;
    localparam STATE_MAC       = 3'b010;
    localparam STATE_DRAIN     = 3'b011;
    localparam STATE_STORE     = 3'b100;
    localparam STATE_NEXT_LAG  = 3'b101;
    localparam STATE_FINISHED  = 3'b110;

    reg [2:0] state;

    // Iteration Counters
    reg [ADDR_CORR-1:0] lag_cnt;   // 0 to TOTAL_LAGS-1
    reg [ADDR_TX-1:0]   n_cnt;     // 0 to N_TX-1
    reg [2:0]           drain_cnt;

    // Control Signals for Multiplier Core
    reg clr_acc;
    reg en_acc;

    // Wire Split for Complex Multiplier Inputs
    wire signed [15:0] tx_i = $signed(tx_dout[31:16]);
    wire signed [15:0] tx_q = $signed(tx_dout[15:0]);
    wire signed [15:0] rx_i = $signed(rx_dout[31:16]);
    wire signed [15:0] rx_q = $signed(rx_dout[15:0]);

    // -------------------------------------------------------------------------
    // Inline 2-Stage Complex MAC Multiplier (avoids sub-module timing issues)
    // -------------------------------------------------------------------------
    // Stage 1: Multiply (1 register stage)
    reg signed [31:0] p_rxi_txi, p_rxq_txq, p_rxq_txi, p_rxi_txq;
    // Stage 2: Add/Subtract (1 register stage)
    reg signed [32:0] prod_real, prod_imag;
    // Accumulator (48-bit)
    reg signed [47:0] acc_real_r, acc_imag_r;
    // Pipeline enables
    reg en_d1, en_d2;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            p_rxi_txi <= 0; p_rxq_txq <= 0;
            p_rxq_txi <= 0; p_rxi_txq <= 0;
            prod_real  <= 0; prod_imag <= 0;
            acc_real_r <= 0; acc_imag_r <= 0;
            en_d1 <= 0; en_d2 <= 0;
        end else begin
            // Stage 1: DSP48 Multiply
            p_rxi_txi <= rx_i * tx_i;
            p_rxq_txq <= rx_q * tx_q;
            p_rxq_txi <= rx_q * tx_i;
            p_rxi_txq <= rx_i * tx_q;
            en_d1 <= en_acc;

            // Stage 2: Complex Add/Subtract
            prod_real <= $signed({{1{p_rxi_txi[31]}}, p_rxi_txi}) +
                         $signed({{1{p_rxq_txq[31]}}, p_rxq_txq});
            prod_imag <= $signed({{1{p_rxq_txi[31]}}, p_rxq_txi}) -
                         $signed({{1{p_rxi_txq[31]}}, p_rxi_txq});
            en_d2 <= en_d1;

            // Stage 3: Accumulate
            if (clr_acc) begin
                acc_real_r <= 48'sd0;
                acc_imag_r <= 48'sd0;
            end else if (en_d2) begin
                acc_real_r <= acc_real_r + $signed({{15{prod_real[32]}}, prod_real});
                acc_imag_r <= acc_imag_r + $signed({{15{prod_imag[32]}}, prod_imag});
            end
        end
    end

    // Wire outputs to top-level
    assign corr_real  = acc_real_r;
    assign corr_imag  = acc_imag_r;
    assign corr_lag   = lag_cnt;
    assign corr_valid = (state == STATE_STORE);
    assign corr_done  = (state == STATE_FINISHED);

    // -------------------------------------------------------------------------
    // Correlator FSM
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= STATE_IDLE;
            lag_cnt   <= 0;
            n_cnt     <= 0;
            drain_cnt <= 0;
            tx_addr   <= 0;
            rx_addr   <= 0;
            clr_acc   <= 1'b0;
            en_acc    <= 1'b0;
        end else begin
            clr_acc <= 1'b0;  // Default: no clear

            case (state)
                // Wait for start pulse from controller
                STATE_IDLE: begin
                    if (start) begin
                        lag_cnt   <= 0;
                        n_cnt     <= 0;
                        drain_cnt <= 0;
                        clr_acc   <= 1'b1;
                        tx_addr   <= 0;
                        rx_addr   <= 0;
                        state     <= STATE_FETCH;
                    end
                end

                // Prime BRAM pipeline with n=0 addresses
                STATE_FETCH: begin
                    tx_addr <= 0;
                    rx_addr <= lag_cnt;
                    en_acc  <= 1'b1;
                    n_cnt   <= 1;
                    state   <= STATE_MAC;
                end

                // Accumulate n=1 to N_TX-1 products
                STATE_MAC: begin
                    tx_addr <= n_cnt;
                    rx_addr <= lag_cnt + n_cnt;

                    if (n_cnt >= N_TX[ADDR_TX-1:0] - 1) begin
                        en_acc    <= 1'b0;
                        drain_cnt <= 3'd3;  // 3 drain cycles for 2-stage pipeline + BRAM
                        state     <= STATE_DRAIN;
                    end else begin
                        n_cnt <= n_cnt + 1'b1;
                    end
                end

                // Drain remaining pipeline contents
                STATE_DRAIN: begin
                    if (drain_cnt > 0) begin
                        drain_cnt <= drain_cnt - 1'b1;
                    end else begin
                        state <= STATE_STORE;
                    end
                end

                // Write accumulated result to correlation RAM (one cycle)
                STATE_STORE: begin
                    state <= STATE_NEXT_LAG;
                end

                // Advance to next lag or finish
                STATE_NEXT_LAG: begin
                    if (lag_cnt >= TOTAL_LAGS[ADDR_CORR-1:0] - 1) begin
                        state <= STATE_FINISHED;
                    end else begin
                        lag_cnt <= lag_cnt + 1'b1;
                        n_cnt   <= 0;
                        clr_acc <= 1'b1;
                        state   <= STATE_FETCH;
                    end
                end

                // Hold FINISHED until controller sees corr_done, then reset
                STATE_FINISHED: begin
                    if (!start) begin
                        state <= STATE_IDLE;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
