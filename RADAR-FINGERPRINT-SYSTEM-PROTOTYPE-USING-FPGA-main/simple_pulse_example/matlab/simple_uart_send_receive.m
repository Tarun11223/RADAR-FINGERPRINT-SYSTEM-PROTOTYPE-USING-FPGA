function [fpga_corr, fpga_peak_index, is_hardware_data] = simple_uart_send_receive(com_port, baud_rate, strict_hw_mode)
% =========================================================================
% Function Name : simple_uart_send_receive
% Project       : Simple Rectangular Pulse Cross-Correlation on FPGA
% Description   : Builds the Rx rectangular pulse signal, transmits it
%                 to Nexys A7 FPGA over USB-UART at 921600 baud, and
%                 captures the 251-lag correlation profile + peak index.
%
% Rx Signal: [0×500 zeros] + [1×1000 ones]  →  N_RX = 1500 samples
%
% UART Byte Protocol (same as main project):
%   TX to FPGA : 4 bytes per sample [Real_Low, Real_High, Imag_Low, Imag_High]
%   RX from FPGA: Magic sync header (4 bytes: 0x5A, 0xA5, peak_low, peak_high)
%                 + 251 × 4 bytes correlation data
%
% Expected Peak: k = 250 → Delay = 2.5 µs → Range = 375 m
% =========================================================================

    if nargin < 1 || isempty(com_port),       com_port       = 'COM4';  end
    if nargin < 2 || isempty(baud_rate),      baud_rate      = 921600;  end
    if nargin < 3 || isempty(strict_hw_mode), strict_hw_mode = false;   end

    N_TX        = 1250;
    N_RX        = 1500;
    TOTAL_LAGS  = N_RX - N_TX + 1;   % 251
    N_ZEROS_TX  = 250;
    N_ONES_TX   = 1000;
    N_ZEROS_RX  = 500;
    N_ONES_RX   = 1000;
    is_hardware_data = false;

    fprintf('=====================================================\n');
    fprintf('  Simple UART Interface (Baud: %d)             \n', baud_rate);
    fprintf('=====================================================\n');
    fprintf('Rx = [%d zeros] + [%d ones]  (N_RX = %d)\n', N_ZEROS_RX, N_ONES_RX, N_RX);

    % -----------------------------------------------------------------------
    % Build Rx Signal: [0×500, 1×1000], real only, imag = 0
    % -----------------------------------------------------------------------
    rx_real_raw = [zeros(N_ZEROS_RX, 1); ones(N_ONES_RX, 1)];
    rx_imag_raw = zeros(N_RX, 1);

    rx_real_q15 = int16(round(min(rx_real_raw, 0.99996948) * 32768));
    rx_imag_q15 = int16(zeros(N_RX, 1));

    % Serialize: [Real_Low, Real_High, Imag_Low, Imag_High] per sample
    tx_bytes = zeros(1, N_RX * 4, 'uint8');
    for i = 1:N_RX
        r_u16 = typecast(rx_real_q15(i), 'uint8');
        i_u16 = typecast(rx_imag_q15(i), 'uint8');
        idx = (i - 1) * 4;
        tx_bytes(idx + 1) = r_u16(1);  % Real Low
        tx_bytes(idx + 2) = r_u16(2);  % Real High
        tx_bytes(idx + 3) = i_u16(1);  % Imag Low
        tx_bytes(idx + 4) = i_u16(2);  % Imag High
    end

    % -----------------------------------------------------------------------
    % Open Serial Port & Communicate
    % -----------------------------------------------------------------------
    try
        s = serialport(com_port, baud_rate, 'Timeout', 20);
        configureTerminator(s, 'LF');
        flush(s);
        fprintf('Opened serial port %s at %d baud.\n', com_port, baud_rate);
        fprintf('Transmitting %d bytes (%d Rx samples) to FPGA...\n', length(tx_bytes), N_RX);
        write(s, tx_bytes, 'uint8');
        fprintf('Awaiting FPGA correlation stream...\n');

        % Read: 1 header word + TOTAL_LAGS correlation words
        total_expected = (1 + TOTAL_LAGS) * 4;  % 1008 bytes
        raw_bytes = read(s, total_expected, 'uint8');
        raw_bytes = raw_bytes(:);
        clear s;

        if length(raw_bytes) < 4
            error('FPGA not responding (%d bytes). Check power and bitstream.', length(raw_bytes));
        end

        % Magic Sync Search: scan for 0x5A 0xA5 pattern
        sync_offset = -1;
        for i = 1:length(raw_bytes)-3
            if raw_bytes(i) == 0x5A && raw_bytes(i+1) == 0xA5
                sync_offset = i;
                break;
            end
        end
        if sync_offset < 0
            error('Magic sync (0x5A 0xA5) not found! Check bitstream programming.');
        end
        fprintf('Magic sync found at byte offset %d\n', sync_offset);

        % Parse peak index from header bytes B2 and B3
        header_b2 = raw_bytes(sync_offset + 2);
        header_b3 = raw_bytes(sync_offset + 3);
        fpga_peak_index = double(typecast(uint8([header_b2, header_b3]), 'uint16'));
        fprintf('*** HARDWARE SUCCESS: Captured %d correlation lags from FPGA! ***\n', TOTAL_LAGS);
        fprintf('FPGA Peak Index: %d samples\n', fpga_peak_index);

        % Parse correlation data: TOTAL_LAGS × 4 bytes after header
        corr_start = sync_offset + 4;
        corr_end   = corr_start + TOTAL_LAGS * 4 - 1;
        if corr_end > length(raw_bytes)
            error('Incomplete stream: got %d bytes, need %d.', length(raw_bytes), corr_end);
        end
        corr_bytes = raw_bytes(corr_start:corr_end);
        bytes_4xN  = reshape(corr_bytes, 4, TOTAL_LAGS);
        r_bytes    = bytes_4xN(1:2, :);
        i_bytes    = bytes_4xN(3:4, :);
        r_vals = double(typecast(r_bytes(:), 'int16')) / 32768.0;
        i_vals = double(typecast(i_bytes(:), 'int16')) / 32768.0;
        fpga_corr = r_vals(:) + 1j * i_vals(:);
        is_hardware_data = true;

    catch ME
        if strict_hw_mode
            error('STRICT HW MODE: %s', ME.message);
        end

        fprintf('\n[NOTICE] Hardware not responding: %s\n', ME.message);
        fprintf('[NOTICE] Running MATLAB software simulation...\n\n');

        % Software simulation
        tx_complex = [zeros(N_ZEROS_TX, 1); ones(N_ONES_TX, 1)];
        rx_complex = [zeros(N_ZEROS_RX, 1); ones(N_ONES_RX, 1)];
        fpga_corr  = zeros(TOTAL_LAGS, 1);
        for k = 1:TOTAL_LAGS
            fpga_corr(k) = sum(rx_complex(k:k+N_TX-1) .* conj(tx_complex));
        end
        fpga_corr       = fpga_corr / N_TX;
        [~, mi]         = max(abs(fpga_corr));
        fpga_peak_index = mi - 1;
        fpga_corr       = fpga_corr(:);
        is_hardware_data = false;
    end
end
