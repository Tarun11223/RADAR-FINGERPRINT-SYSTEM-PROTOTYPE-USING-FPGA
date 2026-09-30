function [fpga_corr, fpga_peak_index, is_hardware_data] = uart_send_receive(com_port, baud_rate, rx_csv_file, strict_hw_mode)
% =========================================================================
% Function Name : uart_send_receive
% Project       : FPGA Radar Matched Filter (Cross-Correlation)
% Description   : Reads Rx radar echo samples from CSV, formats into Q1.15
%                 binary byte stream (Real Low, Real High, Imag Low, Imag High),
%                 transmits to Digilent Nexys A7 over FTDI USB-UART at 921600 baud,
%                 and captures FPGA-computed correlation results & peak index.
%
% UART TX Word Byte Order (from uart_tx.v WSTATE_SEND):
%   B0 = word[23:16]  (Real Low)
%   B1 = word[31:24]  (Real High)
%   B2 = word[7:0]    (Imag Low)
%   B3 = word[15:8]   (Imag High)
%
% Header word in top.v: {8'hA5, 8'h5A, 1'b0, peak_index[14:8], peak_index[7:0]}
%   B0 = 0x5A  (Magic sync byte 1)
%   B1 = 0xA5  (Magic sync byte 2)
%   B2 = peak_index[7:0]   (Imag Low)
%   B3 = {1'b0,peak_index[14:8]} (Imag High)
%
%   => peak_index = typecast([B2, B3], 'uint16')  (little-endian)
% =========================================================================

    if nargin < 1 || isempty(com_port),    com_port     = 'COM3';   end
    if nargin < 2 || isempty(baud_rate),   baud_rate    = 921600;   end
    if nargin < 3 || isempty(rx_csv_file), rx_csv_file  = 'LFM_Chirp_Rx_Data.csv'; end
    if nargin < 4 || isempty(strict_hw_mode), strict_hw_mode = false; end

    N_TX        = 2119;
    N_RX        = 19071;
    TOTAL_LAGS  = N_RX - N_TX + 1;   % 16,953
    is_hardware_data = false;

    fprintf('=====================================================\n');
    fprintf('  MATLAB USB-UART Interface (Baud: %d)            \n', baud_rate);
    fprintf('=====================================================\n');

    % -----------------------------------------------------------------------
    % 1. Load Received Radar Echo Samples from CSV
    % -----------------------------------------------------------------------
    if ~exist(rx_csv_file, 'file')
        error('Rx CSV file %s not found!', rx_csv_file);
    end
    rx_data_tbl = readtable(rx_csv_file, detectImportOptions(rx_csv_file));
    rx_real_raw = rx_data_tbl.Real;
    rx_imag_raw = rx_data_tbl.Imag;
    num_rx = length(rx_real_raw);
    fprintf('Loaded %d Rx samples from %s\n', num_rx, rx_csv_file);

    % -----------------------------------------------------------------------
    % 2. Convert to Signed Q1.15 Int16 & Serialize to 4-byte UART frames
    %    Frame order per sample: [Real_Low, Real_High, Imag_Low, Imag_High]
    % -----------------------------------------------------------------------
    rx_real_q15 = int16(round(max(-1.0, min(0.99996948, rx_real_raw)) * 32768));
    rx_imag_q15 = int16(round(max(-1.0, min(0.99996948, rx_imag_raw)) * 32768));

    tx_bytes = zeros(1, num_rx * 4, 'uint8');
    for i = 1:num_rx
        r_u16 = typecast(rx_real_q15(i), 'uint8');
        i_u16 = typecast(rx_imag_q15(i), 'uint8');
        idx = (i - 1) * 4;
        tx_bytes(idx + 1) = r_u16(1);   % Real Low
        tx_bytes(idx + 2) = r_u16(2);   % Real High
        tx_bytes(idx + 3) = i_u16(1);   % Imag Low
        tx_bytes(idx + 4) = i_u16(2);   % Imag High
    end

    % -----------------------------------------------------------------------
    % 3. Open Serial Port, Transmit Rx Samples, Receive FPGA Correlation Stream
    % -----------------------------------------------------------------------
    try
        s = serialport(com_port, baud_rate, 'Timeout', 30);
        configureTerminator(s, 'LF');
        flush(s);
        fprintf('Opened serial port %s at %d baud.\n', com_port, baud_rate);
        fprintf('Transmitting %d bytes (%d Rx samples) to FPGA...\n', length(tx_bytes), num_rx);

        write(s, tx_bytes, 'uint8');
        fprintf('Awaiting FPGA Peak Search & Correlation Stream...\n');

        % -------------------------------------------------------------------
        % 4. Read full response stream: 1 header word (4 bytes) +
        %    TOTAL_LAGS correlation words (16,953 x 4 bytes) = 67,816 bytes
        % -------------------------------------------------------------------
        total_expected = (1 + TOTAL_LAGS) * 4;   % 67,816 bytes
        raw_bytes = read(s, total_expected, 'uint8');
        raw_bytes = raw_bytes(:);
        clear s;

        if length(raw_bytes) < 4
            error('FPGA hardware is OFF or not responding (%d bytes received). Ensure power is ON and top.bit is programmed.', length(raw_bytes));
        end

        % -------------------------------------------------------------------
        % 5. MAGIC SYNC SEARCH: Scan for 0x5A 0xA5 pattern (header B0 B1)
        %    uart_tx sends: B0=word[23:16]=0x5A, B1=word[31:24]=0xA5
        % -------------------------------------------------------------------
        sync_offset = -1;
        for i = 1 : length(raw_bytes) - 3
            if raw_bytes(i) == 0x5A && raw_bytes(i+1) == 0xA5
                sync_offset = i;
                break;
            end
        end

        if sync_offset < 0
            error('MAGIC SYNC (0x5A 0xA5) not found in FPGA response! Check bitstream and UART connection.');
        end
        fprintf('Magic sync header found at byte offset %d\n', sync_offset);

        % -------------------------------------------------------------------
        % 6. Parse Peak Index from header bytes B2 and B3 (after sync bytes)
        %    Header layout received: [0x5A, 0xA5, peak_low, peak_high]
        %    peak_index (uint16 little-endian) = typecast([B2, B3], 'uint16')
        % -------------------------------------------------------------------
        header_b2 = raw_bytes(sync_offset + 2);  % peak_index[7:0]
        header_b3 = raw_bytes(sync_offset + 3);  % {1'b0, peak_index[14:8]}
        fpga_peak_index = double(typecast(uint8([header_b2, header_b3]), 'uint16'));
        fprintf('*** HARDWARE SUCCESS: Captured 16,953 correlation lags directly from Nexys A7 FPGA! ***\n');
        fprintf('FPGA Peak Index: %d samples\n', fpga_peak_index);

        % -------------------------------------------------------------------
        % 7. Parse Correlation Data: 16,953 x 4 bytes starting after header
        % -------------------------------------------------------------------
        corr_start = sync_offset + 4;
        corr_end   = corr_start + TOTAL_LAGS * 4 - 1;

        if corr_end > length(raw_bytes)
            error('Incomplete correlation stream: expected bytes %d-%d, but only %d bytes received.', ...
                  corr_start, corr_end, length(raw_bytes));
        end

        corr_bytes = raw_bytes(corr_start : corr_end);
        bytes_4xN  = reshape(corr_bytes, 4, TOTAL_LAGS);

        % Byte layout per lag: [Real_Low, Real_High, Imag_Low, Imag_High]
        %   UART sends: B0=word[23:16], B1=word[31:24], B2=word[7:0], B3=word[15:8]
        %   corr_word = {corr_real[15:0], corr_imag[15:0]}
        %   => Real = {B1, B0}, Imag = {B3, B2}  (little-endian int16)
        r_bytes = bytes_4xN(1:2, :);   % [Real_Low; Real_High] for each lag
        i_bytes = bytes_4xN(3:4, :);   % [Imag_Low; Imag_High] for each lag

        r_vals = double(typecast(r_bytes(:), 'int16')) / 32768.0;
        i_vals = double(typecast(i_bytes(:), 'int16')) / 32768.0;

        fpga_corr = r_vals(:) + 1j * i_vals(:);
        is_hardware_data = true;

    catch ME
        if strict_hw_mode
            error('STRICT HARDWARE MODE ERROR: %s', ME.message);
        end

        fprintf('\n-------------------------------------------------------------\n');
        fprintf('  [NOTICE] HARDWARE NOT RESPONDING: %s\n', ME.message);
        fprintf('  [NOTICE] FALLING BACK TO MATLAB SOFTWARE SIMULATION MODE\n');
        fprintf('-------------------------------------------------------------\n\n');

        tx_table   = readtable('LFM_Chirp_Tx_data.csv');
        tx_complex = tx_table.Real + 1j * tx_table.Imag;
        rx_complex = rx_real_raw   + 1j * rx_imag_raw;

        fpga_corr  = zeros(TOTAL_LAGS, 1);
        for k = 1:TOTAL_LAGS
            fpga_corr(k) = sum(rx_complex(k : k + N_TX - 1) .* conj(tx_complex));
        end
        fpga_corr       = fpga_corr / N_TX;
        [~, max_idx]    = max(abs(fpga_corr));
        fpga_peak_index = max_idx - 1;
        fpga_corr       = fpga_corr(:);
        is_hardware_data = false;
    end
end
