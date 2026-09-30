// ============================================================================
// Module Name  : controller
// Project      : FPGA Radar Matched Filter (Cross-Correlation)
// Target FPGA  : Digilent Nexys A7-100T (Artix-7 XC7A100T-1CSG324C)
// Tool Version : Vivado 2024.x / 2025.x
// Description  : Master Control FSM with 9 Discrete States:
//                1. IDLE        - Resets internal pointers and clears FIFO.
//                2. LOAD_TX     - Confirms BRAM Tx initialization completion.
//                3. WAIT_RX     - Awaits incoming UART Rx echo sample stream.
//                4. RECEIVE     - Streams 19,071 Rx samples into FIFO memory.
//                5. CORRELATE   - Triggers Sequential MAC Matched Filter engine.
//                6. STORE       - Awaits 16,953 correlation results in RAM.
//                7. PEAK_SEARCH - Triggers real-time magnitude peak detector.
//                8. TRANSMIT    - Streams correlation profile & peak data over UART.
//                9. DONE        - Reaches completion; asserts status LED outputs.
// ============================================================================

`timescale 1ns / 1ps

module controller #(
    parameter N_TX       = 2119,
    parameter N_RX       = 19071,
    parameter TOTAL_LAGS = 16953,
    parameter ADDR_RX    = 15,
    parameter ADDR_CORR  = 15
)(
    input  wire        clk,
    input  wire        rst,
    
    // Status Inputs
    input  wire [ADDR_RX-1:0]   rx_sample_count,
    input  wire                 corr_done,
    input  wire                 peak_found,
    input  wire                 tx_busy,
    input  wire                 tx_done,
    
    // Control Outputs
    output reg                  clear_fifo,
    output reg                  start_correlator,
    output reg                  start_peak_search,
    output reg                  ram_corr_wea,
    output reg  [ADDR_CORR-1:0] tx_stream_addr,
    output reg                  tx_word_valid,
    output reg  [31:0]          tx_word_data,
    output reg                  stream_peak_header,
    
    // FSM State Vector & Status LEDs
    output wire [3:0]           state_out,
    output reg  [7:0]           led_status
);

    // FSM Encoded State Values
    localparam STATE_IDLE        = 4'd0;
    localparam STATE_LOAD_TX     = 4'd1;
    localparam STATE_WAIT_RX     = 4'd2;
    localparam STATE_RECEIVE     = 4'd3;
    localparam STATE_CORRELATE   = 4'd4;
    localparam STATE_STORE       = 4'd5;
    localparam STATE_PEAK_SEARCH = 4'd6;
    localparam STATE_TRANSMIT    = 4'd7;
    localparam STATE_DONE        = 4'd8;

    reg [3:0] state;
    reg [ADDR_CORR-1:0] tx_idx;
    reg tx_header_sent;
    reg tx_addr_requested;

    assign state_out = state;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state              <= STATE_IDLE;
            clear_fifo         <= 1'b1;
            start_correlator   <= 1'b0;
            start_peak_search  <= 1'b0;
            ram_corr_wea       <= 1'b0;
            tx_stream_addr     <= 0;
            tx_word_valid      <= 1'b0;
            tx_word_data       <= 32'h0;
            stream_peak_header <= 1'b0;
            tx_idx             <= 0;
            tx_header_sent     <= 1'b0;
            tx_addr_requested  <= 1'b0;
            led_status         <= 8'b00000001;
        end else begin
            // Default: clear single-cycle pulse outputs
            start_correlator  <= 1'b0;
            start_peak_search <= 1'b0;
            tx_word_valid     <= 1'b0;
            clear_fifo        <= 1'b0;

            case (state)
                // 1. IDLE State - Reset FIFO pointer
                STATE_IDLE: begin
                    led_status        <= 8'b00000001; // LED0 ON
                    clear_fifo        <= 1'b1;
                    tx_idx            <= 0;
                    tx_header_sent    <= 1'b0;
                    tx_addr_requested <= 1'b0;
                    state             <= STATE_LOAD_TX;
                end

                // 2. LOAD_TX State - Confirm Tx BRAM ready
                STATE_LOAD_TX: begin
                    led_status <= 8'b00000010; // LED1 ON
                    clear_fifo <= 1'b1;
                    state      <= STATE_WAIT_RX;
                end

                // 3. WAIT_RX State - Sit patiently with LED2 ON waiting for UART Rx data
                STATE_WAIT_RX: begin
                    led_status <= 8'b00000100; // LED2 ON ONLY!
                    if (rx_sample_count > 0) begin
                        state <= STATE_RECEIVE;
                    end
                end

                // 4. RECEIVE State - Accumulate 19,071 Rx samples into FIFO
                STATE_RECEIVE: begin
                    led_status <= 8'b00001000; // LED3 ON
                    if (rx_sample_count >= N_RX[ADDR_RX-1:0]) begin
                        start_correlator <= 1'b1; // Trigger correlator
                        state            <= STATE_CORRELATE;
                    end
                end

                // 5. CORRELATE State - Run 16,953 lags at 100 MHz
                STATE_CORRELATE: begin
                    led_status <= 8'b00010000; // LED4 ON
                    if (corr_done) begin
                        state <= STATE_PEAK_SEARCH;
                    end
                end

                // 6. STORE State - Legacy transition
                STATE_STORE: begin
                    state <= STATE_PEAK_SEARCH;
                end

                // 7. PEAK_SEARCH State - Locate peak index
                STATE_PEAK_SEARCH: begin
                    led_status        <= 8'b01000000; // LED6 ON
                    start_peak_search <= 1'b1;
                    if (peak_found) begin
                        tx_idx            <= 0;
                        tx_header_sent    <= 1'b0;
                        tx_addr_requested <= 1'b0;
                        state             <= STATE_TRANSMIT;
                    end
                end

                // 8. TRANSMIT State - Pipelined BRAM read + UART serializer
                STATE_TRANSMIT: begin
                    led_status <= 8'b10000000; // LED7 ON
                    
                    if (!tx_busy && !tx_word_valid && !tx_addr_requested) begin
                        if (!tx_header_sent) begin
                            stream_peak_header <= 1'b1;
                            tx_word_valid      <= 1'b1;
                            tx_header_sent     <= 1'b1;
                        end else begin
                            stream_peak_header <= 1'b0;
                            tx_stream_addr     <= tx_idx;
                            tx_addr_requested  <= 1'b1; // Request BRAM read (1 cycle latency)
                        end
                    end else if (tx_addr_requested) begin
                        tx_word_valid     <= 1'b1;      // Send BRAM output (ready now)
                        tx_addr_requested <= 1'b0;
                        if (tx_idx >= TOTAL_LAGS[ADDR_CORR-1:0] - 1) begin
                            state <= STATE_DONE;
                        end else begin
                            tx_idx <= tx_idx + 1'b1;
                        end
                    end
                end

                // 9. DONE State
                STATE_DONE: begin
                    led_status <= 8'b11111111; // All LEDs ON
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
