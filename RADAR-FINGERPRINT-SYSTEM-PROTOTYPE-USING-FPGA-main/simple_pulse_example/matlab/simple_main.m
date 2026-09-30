% =========================================================================
% Master Script   : simple_main.m
% Project         : Simple Rectangular Pulse Cross-Correlation on FPGA
% Target Hardware : Digilent Nexys A7-100T (Artix-7 XC7A100T)
%
% Theory Example:
%   Tx = [0, 0, ..., 0, 1, 1, ..., 1]   (250 zeros + 1000 ones = 1250 samples)
%   Rx = [0, 0, ..., 0, 1, 1, ..., 1]   (500 zeros + 1000 ones = 1500 samples)
%
%   Cross-Correlation R(k) = sum_{n=0}^{1249} Rx(k+n) × conj(Tx(n))
%
%   Expected Result:
%     R(k) rises linearly from k=0 to peak at k=250
%     PEAK at k = 250  (Rx onset [500] - Tx onset [250] = 250 samples offset)
%     Target Delay = 250 × 10 ns = 2.5 µs
%     Target Range = (3×10^8 × 2.5×10^-6) / 2 = 375 m
%
% Flow:
%   1. Generate simple_tx.mem  (Tx rectangular pulse in Q1.15)
%   2. Compute MATLAB golden cross-correlation reference
%   3. Stream Rx signal to FPGA via USB-UART (COM3, 921600 baud)
%   4. Receive 251-lag correlation profile from FPGA
%   5. Compare FPGA vs MATLAB, plot, report
% =========================================================================

clear; clc; close all;

fprintf('=================================================================\n');
fprintf('  SIMPLE RECTANGULAR PULSE CROSS-CORRELATION — FPGA DEMO        \n');
fprintf('=================================================================\n\n');

% -------------------------------------------------------------------------
% System Parameters
% -------------------------------------------------------------------------
FS        = 100e6;   % 100 MHz sampling rate
C_SPEED   = 3e8;     % Speed of light (m/s)
COM_PORT  = 'COM4';  % FTDI USB-UART port
BAUD_RATE = 921600;

N_ZEROS_TX = 250;
N_ONES_TX  = 1000;
N_ZEROS_RX = 500;
N_ONES_RX  = 1000;

N_TX       = N_ZEROS_TX + N_ONES_TX;   % 1250
N_RX       = N_ZEROS_RX + N_ONES_RX;   % 1500
TOTAL_LAGS = N_RX - N_TX + 1;          % 251

STRICT_HARDWARE_MODE = false;

fprintf('Signal Parameters:\n');
fprintf('  Tx = [%d zeros + %d ones]  → N_TX = %d samples\n', N_ZEROS_TX, N_ONES_TX, N_TX);
fprintf('  Rx = [%d zeros + %d ones]  → N_RX = %d samples\n', N_ZEROS_RX, N_ONES_RX, N_RX);
fprintf('  Total Correlation Lags    = %d\n', TOTAL_LAGS);
fprintf('  Expected Peak at k        = %d samples\n', N_ZEROS_RX - N_ZEROS_TX);
fprintf('  Expected Target Range     = %.3f m (%.4f km)\n', ...
        C_SPEED * (N_ZEROS_RX - N_ZEROS_TX) / FS / 2, ...
        C_SPEED * (N_ZEROS_RX - N_ZEROS_TX) / FS / 2 / 1000);
fprintf('\n');

% -------------------------------------------------------------------------
% Step 1: Generate Tx BRAM Memory File
% -------------------------------------------------------------------------
simple_make_mem();

% -------------------------------------------------------------------------
% Step 2: Build Tx and Rx Signal Vectors (for MATLAB reference)
% -------------------------------------------------------------------------
tx_complex = [zeros(N_ZEROS_TX, 1); ones(N_ONES_TX, 1)];  % real signal
rx_complex = [zeros(N_ZEROS_RX, 1); ones(N_ONES_RX, 1)];  % real signal

% -------------------------------------------------------------------------
% Step 3: Compute MATLAB Golden Float64 Cross-Correlation Reference
% -------------------------------------------------------------------------
fprintf('Computing MATLAB golden cross-correlation reference...\n');
matlab_corr = zeros(TOTAL_LAGS, 1);
for k = 1:TOTAL_LAGS
    matlab_corr(k) = sum(rx_complex(k:k+N_TX-1) .* conj(tx_complex));
end
[~, matlab_peak_idx] = max(abs(matlab_corr));
matlab_peak_lag = matlab_peak_idx - 1;
fprintf('MATLAB Golden Peak Lag: %d samples\n\n', matlab_peak_lag);

% -------------------------------------------------------------------------
% Step 4: Stream Rx Signal to FPGA & Receive Correlation Results
% -------------------------------------------------------------------------
[fpga_corr, fpga_peak_lag, is_hw] = simple_uart_send_receive(COM_PORT, BAUD_RATE, STRICT_HARDWARE_MODE);

% -------------------------------------------------------------------------
% Step 5: Calculate Target Delay & Range
% -------------------------------------------------------------------------
Ts               = 1 / FS;
target_delay_sec = fpga_peak_lag * Ts;
target_delay_us  = target_delay_sec * 1e6;
target_range_m   = (C_SPEED * target_delay_sec) / 2;
target_range_km  = target_range_m / 1000;

% -------------------------------------------------------------------------
% Step 6: Accuracy Metrics (peak-region comparison)
% -------------------------------------------------------------------------
min_len     = min(length(fpga_corr), length(matlab_corr));
fpga_norm   = abs(fpga_corr(1:min_len))   / max(abs(fpga_corr));
matlab_norm = abs(matlab_corr(1:min_len)) / max(abs(matlab_corr));

pk      = fpga_peak_lag + 1;
w       = min(50, pk-1);      % ±50 lag window (safe for small TOTAL_LAGS=251)
p_s     = max(1,       pk - w);
p_e     = min(min_len, pk + w);
nmse    = mean((matlab_norm(p_s:p_e) - fpga_norm(p_s:p_e)).^2) / mean(matlab_norm(p_s:p_e).^2);
cm      = corrcoef(matlab_norm(p_s:p_e), fpga_norm(p_s:p_e));
corr_c  = cm(1,2);

fprintf('=================================================================\n');
fprintf('  SYSTEM PERFORMANCE & ACCURACY EVALUATION                       \n');
fprintf('=================================================================\n');
if is_hw
    fprintf('  EXECUTION SOURCE       : PHYSICAL NEXYS A7 FPGA HARDWARE\n');
else
    fprintf('  EXECUTION SOURCE       : MATLAB SOFTWARE SIMULATION\n');
end
fprintf('  Expected Peak Lag       : %d samples\n', N_ZEROS_RX - N_ZEROS_TX);
fprintf('  MATLAB Peak Lag         : %d samples\n', matlab_peak_lag);
fprintf('  FPGA Output Peak Lag    : %d samples\n', fpga_peak_lag);
fprintf('  Target Delay            : %.4f µs\n',    target_delay_us);
fprintf('  Target Range            : %.4f m  (%.4f km)\n', target_range_m, target_range_km);
fprintf('  NMSE (Peak ±%d lags)    : %.4e\n',       w, nmse);
fprintf('  Cross-Corr Coef         : %.4f (%.2f%% Match)\n', corr_c, corr_c*100);
fprintf('=================================================================\n\n');

% -------------------------------------------------------------------------
% Step 7: Plot Results
% -------------------------------------------------------------------------
simple_plot_results(tx_complex, rx_complex, fpga_corr, matlab_corr, ...
                    fpga_peak_lag, FS, C_SPEED, ...
                    N_ZEROS_TX, N_ONES_TX, N_ZEROS_RX, N_ONES_RX);

fprintf('Simple Cross-Correlation FPGA Demo Completed.\n');
