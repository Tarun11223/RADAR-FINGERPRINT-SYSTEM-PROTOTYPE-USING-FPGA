// ============================================================================
// Module Name  : simple_top
// Project      : Simple Rectangular Pulse Cross-Correlation on FPGA
// Target FPGA  : Digilent Nexys A7-100T (Artix-7 XC7A100T-1CSG324C)
// Tool Version : Vivado 2024.x / 2025.x
// Description  : Top-Level module for the simple rectangular pulse demo.
//                Uses the SAME sub-modules as the LFM chirp radar project
//                (correlator, controller, fifo, bram_tx, peak_detector,
//                uart_rx, uart_tx, ram_corr) with DIFFERENT PARAMETERS:
//
//                Tx Signal : [250 zeros + 1000 ones]  →  N_TX = 1250
//                Rx Signal : [500 zeros + 1000 ones]  →  N_RX = 1500
//                Lags      : N_RX - N_TX + 1          →  TOTAL_LAGS = 251
//
//                Expected Peak  : k = 250 (Rx onset [500] - Tx onset [250])
//                Expected Delay : 250 × 10 ns = 2.5 µs
//                Expected Range : (3×10^8 × 2.5×10^-6) / 2 = 375 m
//
//                BRAM Init File: simple_tx.mem
//                  [0000:0249] = 0x00000000  (zeros in Q1.15 complex)
//                  [0250:1249] = 0x7FFF0000  (Real=+1.0, Imag=0)
//
//                Architecture identical to top.v from radar_cross_corelation.
//                Only N_TX, N_RX, TOTAL_LAGS, address widths, and INIT_FILE differ.
// ============================================================================

`timescale 1ns / 1ps

module simple_top #(
    // *** Key Parameters — different from LFM chirp project ***
    parameter N_TX       = 1250,          // Tx = 250 zeros + 1000 ones
    parameter N_RX       = 1500,          // Rx = 500 zeros + 1000 ones
    parameter TOTAL_LAGS = 251,           // N_RX - N_TX + 1
    // Address widths sized to fit new depths (ceil(log2(depth)))
    parameter ADDR_TX    = 11,            // 2^11 = 2048  > 1250
    parameter ADDR_RX    = 11,            // 2^11 = 2048  > 1500
    parameter ADDR_CORR  = 9,             // 2^9  = 512   > 251
    // Fixed hardware parameters
    parameter CLK_FREQ   = 100000000,     // 100 MHz
    parameter BAUD_RATE  = 921600         // 921,600 Baud
)(
    input  wire       clk,        // 100 MHz System Clock (Pin E3)
    input  wire       rst_n,      // Active Low CPU Reset (Pin C12)
    input  wire       uart_rx_i,  // FPGA RX from PC (Pin C4)
    output wire       uart_tx_o,  // FPGA TX to PC   (Pin D4)
    output wire [7:0] led_o       // Nexys A7 LEDs [7:0]
);

    wire rst = ~rst_n;

    // -----------------------------------------------------------------------
    // Interconnect Wires
    // -----------------------------------------------------------------------
    wire [31:0]          rx_sample_out;
    wire                 rx_sample_valid;
    (* mark_debug = "true" *) wire [ADDR_RX-1:0]   rx_sample_count;
    wire [ADDR_RX-1:0]   fifo_rd_addr;
    wire [31:0]          fifo_rd_data;
    wire                 fifo_full;
    wire                 clear_fifo;

    wire [ADDR_TX-1:0]   bram_tx_rd_addr;
    wire [31:0]          bram_tx_rd_data;

    wire                 start_correlator;
    wire                 corr_valid;
    wire [ADDR_CORR-1:0] corr_lag;
    wire signed [47:0]   corr_real_acc;
    wire signed [47:0]   corr_imag_acc;
    (* mark_debug = "true" *) wire                 corr_done;

    wire                 ram_corr_wea;
    wire [ADDR_CORR-1:0] ram_corr_rd_addr;
    wire [31:0]          ram_corr_rd_data;
    wire [ADDR_CORR-1:0] peak_search_rd_addr;
    wire [ADDR_CORR-1:0] tx_stream_addr;
    wire                 stream_peak_header;

    wire                 start_peak_search;
    (* mark_debug = "true" *) wire [ADDR_CORR-1:0] peak_index;
    wire signed [15:0]   peak_real;
    wire signed [15:0]   peak_imag;
    wire [47:0]          peak_mag_sq;
    wire                 peak_found;

    wire                 tx_busy;
    wire                 tx_done;
    wire                 tx_word_valid;
    wire [31:0]          tx_word_data;
    (* mark_debug = "true" *) wire [3:0]           state_out;

    // -----------------------------------------------------------------------
    // 1. UART RX — Receives Rx samples from MATLAB over USB-UART
    // -----------------------------------------------------------------------
    uart_rx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_rx (
        .clk          (clk),
        .rst          (rst),
        .rxd          (uart_rx_i),
        .byte_out     (),
        .byte_valid   (),
        .sample_out   (rx_sample_out),
        .sample_valid (rx_sample_valid)
    );

    // -----------------------------------------------------------------------
    // 2. Rx Sample FIFO — Buffers 1500 Rx samples (N_RX = 1500)
    // -----------------------------------------------------------------------
    fifo #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (ADDR_RX),    // 11-bit → 2048 addressable entries
        .MAX_DEPTH  (N_RX)        // 1500
    ) u_rx_fifo (
        .clk          (clk),
        .rst          (rst),
        .clr          (clear_fifo),
        .wr_en        (rx_sample_valid),
        .din          (rx_sample_out),
        .full         (fifo_full),
        .wr_ptr       (rx_sample_count),
        .rd_addr      (fifo_rd_addr),
        .dout         (fifo_rd_data),
        .sample_count ()
    );

    // -----------------------------------------------------------------------
    // 3. Tx Signal BRAM — Holds 1250-sample rectangular Tx pulse
    //    INIT_FILE: simple_tx.mem
    //      [0000:0249] = 0x00000000  (250 zeros in Q1.15)
    //      [0250:1249] = 0x7FFF0000  (1000 ones:  Real=+1.0, Imag=0)
    // -----------------------------------------------------------------------
    bram_tx #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (ADDR_TX),    // 11-bit → 2048 addressable entries
        .MEM_DEPTH  (N_TX),       // 1250
        .INIT_FILE  ("simple_tx.mem")
    ) u_bram_tx (
        .clk   (clk),
        .wea   (1'b0),
        .addra (11'd0),
        .dina  (32'd0),
        .douta (),
        .addrb (bram_tx_rd_addr),
        .doutb (bram_tx_rd_data)
    );

    // -----------------------------------------------------------------------
    // 4. Sequential Complex MAC Correlator
    //    Computes R(k) = sum_{n=0}^{1249} Rx(k+n) × conj(Tx(n)) for 251 lags
    // -----------------------------------------------------------------------
    correlator #(
        .N_TX       (N_TX),        // 1250
        .N_RX       (N_RX),        // 1500
        .TOTAL_LAGS (TOTAL_LAGS),  // 251
        .ADDR_TX    (ADDR_TX),     // 11
        .ADDR_RX    (ADDR_RX),     // 11
        .ADDR_CORR  (ADDR_CORR)    // 9
    ) u_correlator (
        .clk        (clk),
        .rst        (rst),
        .start      (start_correlator),
        .tx_dout    (bram_tx_rd_data),
        .rx_dout    (fifo_rd_data),
        .tx_addr    (bram_tx_rd_addr),
        .rx_addr    (fifo_rd_addr),
        .corr_valid (corr_valid),
        .corr_lag   (corr_lag),
        .corr_real  (corr_real_acc),
        .corr_imag  (corr_imag_acc),
        .corr_done  (corr_done)
    );

    // 48-bit MAC → Q1.15 16-bit scaling (arithmetic right-shift by 27)
    // Max accumulator for rectangular pulse: 1000 × 32767² ≈ 2^40
    // After >>> 27: ~2^13 which fits in Q1.15 range
    wire signed [47:0] corr_real_shifted = corr_real_acc >>> 27;
    wire signed [47:0] corr_imag_shifted = corr_imag_acc >>> 27;

    wire signed [15:0] corr_real_scaled = (corr_real_shifted > 47'sd32767)  ?  16'sd32767 :
                                          (corr_real_shifted < -47'sd32768) ? -16'sd32768 :
                                           corr_real_shifted[15:0];
    wire signed [15:0] corr_imag_scaled = (corr_imag_shifted > 47'sd32767)  ?  16'sd32767 :
                                          (corr_imag_shifted < -47'sd32768) ? -16'sd32768 :
                                           corr_imag_shifted[15:0];

    wire [31:0] corr_word_scaled = {corr_real_scaled, corr_imag_scaled};

    // RAM read address mux: peak_detector (state 6) vs UART transmitter
    localparam STATE_PEAK_SEARCH = 4'd6;
    assign ram_corr_rd_addr = (stream_peak_header) ? {ADDR_CORR{1'b0}} :
                              (state_out == STATE_PEAK_SEARCH) ? peak_search_rd_addr :
                              tx_stream_addr;

    // -----------------------------------------------------------------------
    // 5. Correlation Results RAM — 251 lags × 32-bit
    // -----------------------------------------------------------------------
    ram_corr #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (ADDR_CORR),   // 9-bit → 512 addressable entries
        .MAX_DEPTH  (TOTAL_LAGS)   // 251
    ) u_ram_corr (
        .clk   (clk),
        .wea   (corr_valid),
        .addra (corr_lag),
        .dina  (corr_word_scaled),
        .addrb (ram_corr_rd_addr),
        .doutb (ram_corr_rd_data)
    );

    // -----------------------------------------------------------------------
    // 6. Peak Detector — Finds maximum |R(k)| across all 251 lags
    //    Expected output: peak_index = 250
    // -----------------------------------------------------------------------
    peak_detector #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (ADDR_CORR),   // 9
        .MAX_DEPTH  (TOTAL_LAGS)   // 251
    ) u_peak_detector (
        .clk          (clk),
        .rst          (rst),
        .start_search (start_peak_search),
        .rd_addr      (peak_search_rd_addr),
        .corr_din     (ram_corr_rd_data),
        .peak_index   (peak_index),
        .peak_real    (peak_real),
        .peak_imag    (peak_imag),
        .peak_mag_sq  (peak_mag_sq),
        .peak_found   (peak_found)
    );

    // -----------------------------------------------------------------------
    // 7. UART TX — Streams correlation profile + peak to MATLAB
    //    Header: {8'hA5, 8'h5A, 1'b0, peak_index[7:1], peak_index[0], 8'd0}
    // -----------------------------------------------------------------------
    // Zero-pad peak_index (ADDR_CORR=9 bits) to 16 bits so header is always 32 bits:
    // {8'hA5, 8'h5A, peak_high_byte, peak_low_byte} = 8+8+8+8 = 32 bits always correct
    wire [15:0] peak_idx_16    = {{(16-ADDR_CORR){1'b0}}, peak_index};  // e.g. 0x00FA for k=250
    wire [31:0] peak_header_word = {8'hA5, 8'h5A, peak_idx_16[15:8], peak_idx_16[7:0]};
    wire [31:0] tx_stream_word   = (stream_peak_header) ? peak_header_word : ram_corr_rd_data;

    uart_tx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_tx (
        .clk           (clk),
        .rst           (rst),
        .tx_byte       (8'h00),
        .tx_byte_valid (1'b0),
        .tx_word       (tx_stream_word),
        .tx_word_valid (tx_word_valid),
        .txd           (uart_tx_o),
        .tx_busy       (tx_busy),
        .tx_done       (tx_done)
    );

    // -----------------------------------------------------------------------
    // 8. Master FSM Controller
    // -----------------------------------------------------------------------
    controller #(
        .N_TX       (N_TX),        // 1250
        .N_RX       (N_RX),        // 1500
        .TOTAL_LAGS (TOTAL_LAGS),  // 251
        .ADDR_RX    (ADDR_RX),     // 11
        .ADDR_CORR  (ADDR_CORR)    // 9
    ) u_controller (
        .clk                (clk),
        .rst                (rst),
        .rx_sample_count    (rx_sample_count),
        .corr_done          (corr_done),
        .peak_found         (peak_found),
        .tx_busy            (tx_busy),
        .tx_done            (tx_done),
        .clear_fifo         (clear_fifo),
        .start_correlator   (start_correlator),
        .start_peak_search  (start_peak_search),
        .ram_corr_wea       (ram_corr_wea),
        .tx_stream_addr     (tx_stream_addr),
        .tx_word_valid      (tx_word_valid),
        .tx_word_data       (tx_word_data),
        .stream_peak_header (stream_peak_header),
        .state_out          (state_out),
        .led_status         (led_o)
    );

endmodule
