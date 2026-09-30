// ============================================================================
// Module Name  : uart_tx
// Project      : FPGA Radar Matched Filter (Cross-Correlation)
// Target FPGA  : Digilent Nexys A7-100T (Artix-7 XC7A100T-1CSG324C)
// Tool Version : Vivado 2024.x
// Description  : High-Speed Synthesizable UART Transmitter operating at 921600 baud
//                on a 100 MHz System Clock (108.5 clocks per bit).
//                Supports both single-byte transmission and 32-bit IQ word
//                streaming (4 bytes: Real Low, Real High, Imag Low, Imag High).
// ============================================================================

`timescale 1ns / 1ps

module uart_tx #(
    parameter CLK_FREQ  = 100000000, // 100 MHz
    parameter BAUD_RATE = 921600     // 921,600 Baud Rate
)(
    input  wire        clk,
    input  wire        rst,
    
    // Single Byte Interface
    input  wire [7:0]  tx_byte,
    input  wire        tx_byte_valid,
    
    // 32-bit IQ Word Interface
    input  wire [31:0] tx_word,       // {Real[15:0], Imag[15:0]}
    input  wire        tx_word_valid,
    
    // Serial Output & Status
    output reg         txd,
    output wire        tx_busy,
    output reg         tx_done
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE; // ~108 cycles @ 100MHz

    // Serial Byte Transmitter FSM States
    localparam STATE_IDLE  = 2'b00;
    localparam STATE_START = 2'b01;
    localparam STATE_DATA  = 2'b10;
    localparam STATE_STOP  = 2'b11;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  tx_shift_reg;
    reg        byte_active;

    // Word Serializer FSM States
    localparam WSTATE_IDLE = 2'b00;
    localparam WSTATE_SEND = 2'b01;

    reg [1:0]  wstate;
    reg [2:0]  word_byte_idx;
    reg [31:0] word_buffer;
    reg        send_byte_req;
    reg [7:0]  send_byte_data;

    assign tx_busy = (state != STATE_IDLE) || (wstate != WSTATE_IDLE);

    // Byte Transmitter FSM
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= STATE_IDLE;
            clk_cnt      <= 0;
            bit_idx      <= 0;
            tx_shift_reg <= 8'h00;
            txd          <= 1'b1; // Idle line HIGH
            byte_active  <= 1'b0;
            tx_done      <= 1'b0;
        end else begin
            tx_done <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    txd     <= 1'b1;
                    clk_cnt <= 0;
                    bit_idx <= 0;

                    if (tx_byte_valid || send_byte_req) begin
                        tx_shift_reg <= (send_byte_req) ? send_byte_data : tx_byte;
                        byte_active  <= 1'b1;
                        state        <= STATE_START;
                    end
                end

                STATE_START: begin
                    txd <= 1'b0; // Start bit LOW
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        state   <= STATE_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                STATE_DATA: begin
                    txd <= tx_shift_reg[bit_idx]; // LSB first
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 0;
                            state   <= STATE_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                STATE_STOP: begin
                    txd <= 1'b1; // Stop bit HIGH
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt     <= 0;
                        byte_active <= 1'b0;
                        tx_done     <= 1'b1;
                        state       <= STATE_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

    // 32-bit Word Serialization Engine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wstate         <= WSTATE_IDLE;
            word_byte_idx  <= 0;
            word_buffer    <= 32'h00000000;
            send_byte_req  <= 1'b0;
            send_byte_data <= 8'h00;
        end else begin
            send_byte_req <= 1'b0;

            case (wstate)
                WSTATE_IDLE: begin
                    if (tx_word_valid) begin
                        word_buffer   <= tx_word;
                        word_byte_idx <= 0;
                        wstate        <= WSTATE_SEND;
                    end
                end

                WSTATE_SEND: begin
                    if (state == STATE_IDLE && !send_byte_req) begin
                        case (word_byte_idx)
                            3'd0: send_byte_data <= word_buffer[23:16]; // Real Low Byte
                            3'd1: send_byte_data <= word_buffer[31:24]; // Real High Byte
                            3'd2: send_byte_data <= word_buffer[7:0];   // Imag Low Byte
                            3'd3: send_byte_data <= word_buffer[15:8];  // Imag High Byte
                        endcase
                        
                        send_byte_req <= 1'b1;
                        
                        if (word_byte_idx == 3'd3) begin
                            wstate <= WSTATE_IDLE;
                        end else begin
                            word_byte_idx <= word_byte_idx + 1'b1;
                        end
                    end
                end

                default: wstate <= WSTATE_IDLE;
            endcase
        end
    end

endmodule
