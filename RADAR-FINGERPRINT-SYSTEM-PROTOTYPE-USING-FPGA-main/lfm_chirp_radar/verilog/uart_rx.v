// ============================================================================
// Module Name  : uart_rx
// Project      : FPGA Radar Matched Filter (Cross-Correlation)
// Target FPGA  : Digilent Nexys A7-100T (Artix-7 XC7A100T-1CSG324C)
// Tool Version : Vivado 2024.x
// Description  : High-Speed Synthesizable UART Receiver operating at 921600 baud
//                on a 100 MHz System Clock (108.5 clocks per bit).
//                Uses 16x oversampling / mid-bit sampling.
//                Assembles 4 incoming binary bytes into 32-bit IQ sample:
//                {Real_High, Real_Low, Imag_High, Imag_Low}.
// ============================================================================

`timescale 1ns / 1ps

module uart_rx #(
    parameter CLK_FREQ  = 100000000, // 100 MHz
    parameter BAUD_RATE = 921600     // 921,600 Baud Rate
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        rxd,          // Serial Rx line input
    
    // Byte-level Interface
    output reg  [7:0]  byte_out,
    output reg         byte_valid,
    
    // 32-bit IQ Word Assembly Interface
    output reg  [31:0] sample_out,   // {Real[15:0], Imag[15:0]}
    output reg         sample_valid
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE; // ~108 cycles @ 100MHz
    localparam HALF_BIT     = CLKS_PER_BIT / 2;     // ~54 cycles

    // RX Synchronizer (prevent metastability)
    reg rxd_sync1, rxd_sync2;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rxd_sync1 <= 1'b1;
            rxd_sync2 <= 1'b1;
        end else begin
            rxd_sync1 <= rxd;
            rxd_sync2 <= rxd_sync1;
        end
    end

    // UART Receiver State Machine
    localparam STATE_IDLE  = 2'b00;
    localparam STATE_START = 2'b01;
    localparam STATE_DATA  = 2'b10;
    localparam STATE_STOP  = 2'b11;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  rx_shift_reg;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= STATE_IDLE;
            clk_cnt      <= 0;
            bit_idx      <= 0;
            rx_shift_reg <= 8'h00;
            byte_out     <= 8'h00;
            byte_valid   <= 1'b0;
        end else begin
            byte_valid <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    if (rxd_sync2 == 1'b0) begin // Start bit detected (falling edge)
                        state <= STATE_START;
                    end
                end

                STATE_START: begin
                    if (clk_cnt == HALF_BIT - 1) begin
                        if (rxd_sync2 == 1'b0) begin // Verify start bit at midpoint
                            clk_cnt <= 0;
                            state   <= STATE_DATA;
                        end else begin
                            state   <= STATE_IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                STATE_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt               <= 0;
                        rx_shift_reg[bit_idx] <= rxd_sync2; // LSB first
                        
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
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        byte_out   <= rx_shift_reg;
                        byte_valid <= 1'b1;
                        clk_cnt    <= 0;
                        state      <= STATE_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

    // Byte to 32-bit IQ Word Assembler
    // Frame: Byte 0 = Real Low, Byte 1 = Real High, Byte 2 = Imag Low, Byte 3 = Imag High
    reg [1:0] byte_cnt;
    reg [7:0] real_low, real_high, imag_low;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            byte_cnt     <= 2'd0;
            real_low     <= 8'h00;
            real_high    <= 8'h00;
            imag_low     <= 8'h00;
            sample_out   <= 32'h00000000;
            sample_valid <= 1'b0;
        end else begin
            sample_valid <= 1'b0;

            if (byte_valid) begin
                case (byte_cnt)
                    2'd0: begin
                        real_low <= byte_out;
                        byte_cnt <= 2'd1;
                    end
                    2'd1: begin
                        real_high <= byte_out;
                        byte_cnt  <= 2'd2;
                    end
                    2'd2: begin
                        imag_low <= byte_out;
                        byte_cnt <= 2'd3;
                    end
                    2'd3: begin
                        sample_out   <= {real_high, real_low, byte_out, imag_low}; // {Real[15:0], Imag[15:0]}
                        sample_valid <= 1'b1;
                        byte_cnt     <= 2'd0;
                    end
                endcase
            end
        end
    end

endmodule
