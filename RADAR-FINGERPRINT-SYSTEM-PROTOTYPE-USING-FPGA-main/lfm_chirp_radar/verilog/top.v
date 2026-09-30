// ============================================================================
// Module Name  : top
// Project      : FPGA Radar Matched Filter (Cross-Correlation)
// Target FPGA  : Digilent Nexys A7-100T (Artix-7 XC7A100T-1CSG324C)
// Tool Version : Vivado 2024.x / 2025.x
// Description  : Top-Level Synthesizable Module integrating BRAM, FIFO, Sequential
//                Complex MAC Correlator, Correlation RAM, Peak Detector, UART RX/TX,
//                and 9-State Master Controller FSM.
//                Includes Magic Sync Header 0xA55A for UART framing.
// ============================================================================

`timescale 1ns / 1ps

module top #(
    parameter N_TX       = 2119,
    parameter N_RX       = 19071,
    parameter TOTAL_LAGS = 16953,
    parameter CLK_FREQ  = 100000000, // 100 MHz
    parameter BAUD_RATE = 921600     // 921,600 Baud
)(
    input  wire       clk,        // 100 MHz System Clock (Pin E3)
    input  wire       rst_n,      // Active Low CPU Reset (Pin C12)
    
    // USB-UART FTDI Serial Interface
    (* mark_debug = "true" *) input  wire       uart_rx_i,  // FPGA RX line (Pin C4)
    (* mark_debug = "true" *) output wire       uart_tx_o,  // FPGA TX line (Pin D4)
    
    // Status LEDs
    output wire [7:0] led_o       // Nexys A7 LEDs [7:0] (Pins H17..J15)
);

    // Active High Internal Reset
    wire rst = ~rst_n;

    // ------------------------------------------------------------------------
    // Interconnect Wires & Signals (Declared with ILA Debug Marks)
    // ------------------------------------------------------------------------
    wire [31:0] rx_sample_out;
    wire        rx_sample_valid;

    (* mark_debug = "true" *) wire [14:0] rx_sample_count;
    wire [14:0] fifo_rd_addr;
    wire [31:0] fifo_rd_data;
    wire        fifo_full;
    wire        clear_fifo;

    wire [11:0] bram_tx_rd_addr;
    wire [31:0] bram_tx_rd_data;

    wire        start_correlator;
    wire        corr_valid;
    wire [14:0] corr_lag;
    wire signed [47:0] corr_real_acc;
    wire signed [47:0] corr_imag_acc;
    (* mark_debug = "true" *) wire        corr_done;

    wire        ram_corr_wea;
    wire [14:0] ram_corr_rd_addr;
    wire [31:0] ram_corr_rd_data;
    wire [14:0] peak_search_rd_addr;
    wire [14:0] tx_stream_addr;
    wire        stream_peak_header;

    wire        start_peak_search;
    (* mark_debug = "true" *) wire [14:0] peak_index;
    wire signed [15:0] peak_real;
    wire signed [15:0] peak_imag;
    wire [47:0] peak_mag_sq;
    wire        peak_found;

    wire        tx_busy;
    wire        tx_done;
    wire        tx_word_valid;
    wire [31:0] tx_word_data;
    (* mark_debug = "true" *) wire [3:0]  state_out;

    // ------------------------------------------------------------------------
    // 1. UART RX Interface & IQ Word Receiver
    // ------------------------------------------------------------------------
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

    // ------------------------------------------------------------------------
    // 2. Rx Signal Buffer / FIFO RAM (19,071 Depth x 32-bit Width)
    // ------------------------------------------------------------------------
    fifo #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (15),
        .MAX_DEPTH  (N_RX)
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

    // ------------------------------------------------------------------------
    // 3. Transmit Chirp BRAM (2,119 Depth x 32-bit Width)
    // ------------------------------------------------------------------------
    bram_tx #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (12),
        .MEM_DEPTH  (N_TX),
        .INIT_FILE  ("tx.mem")
    ) u_bram_tx (
        .clk   (clk),
        .wea   (1'b0),
        .addra (12'd0),
        .dina  (32'd0),
        .douta (),
        .addrb (bram_tx_rd_addr),
        .doutb (bram_tx_rd_data)
    );

    // ------------------------------------------------------------------------
    // 4. Sequential Complex MAC Matched Filter Correlator
    // ------------------------------------------------------------------------
    correlator #(
        .N_TX       (N_TX),
        .N_RX       (N_RX),
        .TOTAL_LAGS (TOTAL_LAGS),
        .ADDR_TX    (12),
        .ADDR_RX    (15),
        .ADDR_CORR  (15)
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

    // Scaling 48-bit MAC outputs to 16-bit signed Q1.15 values for RAM storage
    // Arithmetic Right Shift by 27 bits (normalizes by N_Tx = 2119 and maps Q13.30 -> Q1.15)
    wire signed [47:0] corr_real_shifted = corr_real_acc >>> 27;
    wire signed [47:0] corr_imag_shifted = corr_imag_acc >>> 27;

    // Signed Saturation logic to 16-bit signed range [-32768, +32767]
    wire signed [15:0] corr_real_scaled = (corr_real_shifted > 47'sd32767)  ? 16'sd32767 :
                                          (corr_real_shifted < -47'sd32768) ? -16'sd32768 :
                                          corr_real_shifted[15:0];

    wire signed [15:0] corr_imag_scaled = (corr_imag_shifted > 47'sd32767)  ? 16'sd32767 :
                                          (corr_imag_shifted < -47'sd32768) ? -16'sd32768 :
                                          corr_imag_shifted[15:0];

    wire [31:0] corr_word_scaled = {corr_real_scaled, corr_imag_scaled};

    // Multiplex read address to Correlation RAM (Peak Detector vs UART TX Streamer)
    // STATE_PEAK_SEARCH = 4'd6
    assign ram_corr_rd_addr = (stream_peak_header) ? 15'd0 :
                              (state_out == 4'd6)   ? peak_search_rd_addr : tx_stream_addr;

    // ------------------------------------------------------------------------
    // 5. Correlation Results RAM (16,953 Depth x 32-bit Width)
    // ------------------------------------------------------------------------
    ram_corr #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (15),
        .MAX_DEPTH  (TOTAL_LAGS)
    ) u_ram_corr (
        .clk   (clk),
        .wea   (corr_valid),
        .addra (corr_lag),
        .dina  (corr_word_scaled),
        .addrb (ram_corr_rd_addr),
        .doutb (ram_corr_rd_data)
    );

    // ------------------------------------------------------------------------
    // 6. Real-Time Radar Peak Detector Module
    // ------------------------------------------------------------------------
    peak_detector #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (15),
        .MAX_DEPTH  (TOTAL_LAGS)
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

    // ------------------------------------------------------------------------
    // 7. UART TX Interface & Word Serializer Streamer
    // Magic Sync Pattern Header: 0xA55A + 16-bit Peak Index
    // ------------------------------------------------------------------------
    wire [31:0] peak_header_word = {8'hA5, 8'h5A, 1'b0, peak_index[14:8], peak_index[7:0]};
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

    // ------------------------------------------------------------------------
    // 8. Master FSM Controller Module
    // ------------------------------------------------------------------------
    controller #(
        .N_TX       (N_TX),
        .N_RX       (N_RX),
        .TOTAL_LAGS (TOTAL_LAGS),
        .ADDR_RX    (15),
        .ADDR_CORR  (15)
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
