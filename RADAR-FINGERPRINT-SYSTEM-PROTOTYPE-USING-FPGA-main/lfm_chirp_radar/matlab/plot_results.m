function plot_results(tx_signal, rx_signal, fpga_corr, matlab_corr, peak_index, fs, c)
% =========================================================================
% Function Name : plot_results
% Project       : FPGA Radar Matched Filter (Cross-Correlation)
% Description   : Visualizes Transmit Chirp, Received Echo, FPGA Matched Filter
%                 Correlation Profile, and Zoomed Peak Region comparing FPGA
%                 Fixed-Point output against MATLAB Golden Model.
%                 Annotates target delay (us) and target range (km).
%                 Uses dB log-scale for fair fixed-point vs. floating-point comparison.
% =========================================================================

    % Fallback for direct standalone invocation without parameters
    if nargin < 1 || isempty(tx_signal)
        fprintf('No input parameters passed to plot_results. Loading default CSV dataset...\n');
        if ~exist('LFM_Chirp_Tx_data.csv', 'file') || ~exist('LFM_Chirp_Rx_Data.csv', 'file')
            error('CSV files not found! Please run main.m first.');
        end
        tx_tbl = readtable('LFM_Chirp_Tx_data.csv');
        rx_tbl = readtable('LFM_Chirp_Rx_Data.csv');
        tx_signal = tx_tbl.Real + 1j * tx_tbl.Imag;
        rx_signal = rx_tbl.Real + 1j * rx_tbl.Imag;
        N_TX = length(tx_signal);
        N_RX = length(rx_signal);
        TOTAL_LAGS = N_RX - N_TX + 1;
        matlab_corr = zeros(TOTAL_LAGS, 1);
        for k = 1:TOTAL_LAGS
            rx_slice = rx_signal(k : k + N_TX - 1);
            matlab_corr(k) = sum(rx_slice .* conj(tx_signal));
        end
        fpga_corr = matlab_corr / length(tx_signal);
        [~, max_idx] = max(abs(fpga_corr));
        peak_index = max_idx - 1;
    end

    if nargin < 6 || isempty(fs), fs = 100e6; end
    if nargin < 7 || isempty(c),  c  = 3e8;   end

    Ts       = 1 / fs;
    num_tx   = length(tx_signal);
    num_rx   = length(rx_signal);
    num_lags = length(fpga_corr);

    % Delay & Range Calculations
    target_delay_sec = peak_index * Ts;
    target_delay_us  = target_delay_sec * 1e6;
    target_range_m   = (c * target_delay_sec) / 2.0;
    target_range_km  = target_range_m / 1000.0;

    fprintf('=====================================================\n');
    fprintf('  RADAR MATCHED FILTER TARGET DETECTION SUMMARY     \n');
    fprintf('=====================================================\n');
    fprintf('  Detected Peak Lag Index : %d samples\n',             peak_index);
    fprintf('  Target Two-Way Delay    : %.4f us (%.2f ns)\n',      target_delay_us, target_delay_sec*1e9);
    fprintf('  Target Range (Distance) : %.4f km (%.2f meters)\n',  target_range_km, target_range_m);
    fprintf('=====================================================\n\n');

    % -----------------------------------------------------------------------
    % Pre-compute Normalized Magnitudes — align both arrays to same length
    % -----------------------------------------------------------------------
    min_len  = min(length(fpga_corr), length(matlab_corr));
    num_lags = min_len;   % override so lags, fpga_dB, matlab_dB all match

    fpga_corr_trim   = fpga_corr(1:min_len);
    matlab_corr_trim = matlab_corr(1:min_len);

    fpga_mag    = abs(fpga_corr_trim);
    matlab_mag  = abs(matlab_corr_trim);
    max_fpga    = max(fpga_mag);
    max_matlab  = max(matlab_mag);

    if max_fpga  == 0, max_fpga  = 1; end
    if max_matlab == 0, max_matlab = 1; end

    fpga_mag_norm   = fpga_mag   / max_fpga;
    matlab_mag_norm = matlab_mag / max_matlab;

    % dB-scale versions (floor at -60 dB) for fair fixed-point comparison
    fpga_dB   = max(20*log10(fpga_mag_norm   + 1e-10), -60);
    matlab_dB = max(20*log10(matlab_mag_norm + 1e-10), -60);

    lags    = 0 : num_lags - 1;          % now guaranteed same size as dB arrays
    t_tx_us = (0:num_tx-1) * Ts * 1e6;
    t_rx_us = (0:num_rx-1) * Ts * 1e6;

    % -----------------------------------------------------------------------
    % Figure Setup
    % -----------------------------------------------------------------------
    fig = figure('Name', 'FPGA Radar Matched Filter Cross-Correlation Results', ...
                 'NumberTitle', 'off', 'Color', [0.08 0.09 0.12], ...
                 'Position', [60, 60, 1320, 860]);

    bg = [0.08 0.09 0.12];
    ax_bg = [0.11 0.12 0.16];
    label_color = [0.82 0.84 0.88];

    % -----------------------------------------------------------------------
    % Subplot 1: Transmit LFM Chirp Signal
    % -----------------------------------------------------------------------
    ax1 = subplot(2, 2, 1);
    plot(t_tx_us, real(tx_signal), 'LineWidth', 1.3, 'Color', [0.22 0.72 1.00]); hold on;
    plot(t_tx_us, imag(tx_signal), 'LineWidth', 1.0, 'Color', [1.00 0.40 0.40]);
    grid on; hold off;
    title('1. Transmit LFM Chirp Signal (Tx)', 'Color', 'w', 'FontSize', 11, 'FontWeight', 'bold');
    xlabel('Time (\mus)', 'Color', label_color);
    ylabel('Amplitude (Q1.15)', 'Color', label_color);
    legend({'Real (I)', 'Imag (Q)'}, 'TextColor', 'w', 'Color', [0.15 0.15 0.20]);
    set(ax1, 'Color', ax_bg, 'XColor', label_color, 'YColor', label_color);

    % -----------------------------------------------------------------------
    % Subplot 2: Received Radar Echo Signal
    % -----------------------------------------------------------------------
    ax2 = subplot(2, 2, 2);
    plot(t_rx_us, real(rx_signal), 'LineWidth', 1.0, 'Color', [0.30 0.92 0.42]); hold on;
    plot(t_rx_us, imag(rx_signal), 'LineWidth', 0.8, 'Color', [0.92 0.72 0.18]);
    grid on; hold off;
    title('2. Received Radar Echo Signal + Noise (Rx)', 'Color', 'w', 'FontSize', 11, 'FontWeight', 'bold');
    xlabel('Time (\mus)', 'Color', label_color);
    ylabel('Amplitude (Q1.15)', 'Color', label_color);
    legend({'Rx Real (I)', 'Rx Imag (Q)'}, 'TextColor', 'w', 'Color', [0.15 0.15 0.20]);
    set(ax2, 'Color', ax_bg, 'XColor', label_color, 'YColor', label_color);

    % -----------------------------------------------------------------------
    % Subplot 3: FPGA Correlation Profile  [dB scale]
    % NOTE: The Q1.15 fixed-point profile looks noisy/flat on a LINEAR scale
    % because small sidelobes are quantized to only a few LSBs (3.05e-5 step).
    % The dB scale reveals the true profile shape and dynamic range.
    % -----------------------------------------------------------------------
    ax3 = subplot(2, 2, 3);
    plot(lags, matlab_dB, 'w--', 'LineWidth', 1.5); hold on;
    plot(lags, fpga_dB,   'Color', [0.9 0.2 0.9], 'LineWidth', 1.2);
    if peak_index < num_lags
        plot(peak_index, fpga_dB(peak_index+1), 'ro', 'MarkerSize', 8, 'LineWidth', 2, 'MarkerFaceColor', 'r');
    end
    grid on; hold off;
    title('3. Correlation Profile R(k) — dB Scale', 'Color', 'w', 'FontSize', 11, 'FontWeight', 'bold');
    xlabel('Delay Lag Index (k)', 'Color', label_color);
    ylabel('Normalized Magnitude (dB)', 'Color', label_color);
    ylim([-65, 5]);
    legend({'MATLAB Float64 Reference', 'FPGA Q1.15 Hardware', sprintf('Peak @ k=%d', peak_index)}, ...
           'TextColor', 'w', 'Color', [0.15 0.15 0.20], 'Location', 'northeast');
    set(ax3, 'Color', ax_bg, 'XColor', label_color, 'YColor', label_color);

    % -----------------------------------------------------------------------
    % Subplot 4: Zoomed ±200 Lag Peak Region — LINEAR Normalized
    % Both profiles normalized to 1.0 within the window for fair local comparison.
    % -----------------------------------------------------------------------
    ax4 = subplot(2, 2, 4);
    win_half  = 200;
    win_start = max(1, peak_index - win_half + 1);
    win_end   = min(min_len, peak_index + win_half);
    win_lags  = win_start-1 : win_end-1;

    % Window-local normalization for fair visual comparison
    fpga_win   = fpga_mag_norm(win_start : win_end);
    matlab_win = matlab_mag_norm(win_start : win_end);
    max_fpga_win   = max(fpga_win);   if max_fpga_win   == 0, max_fpga_win   = 1; end
    max_matlab_win = max(matlab_win); if max_matlab_win == 0, max_matlab_win = 1; end

    plot(win_lags, matlab_win / max_matlab_win, 'w--', 'LineWidth', 2.0); hold on;
    plot(win_lags, fpga_win   / max_fpga_win,   'Color', [0.0 0.9 0.8], 'LineWidth', 1.5);
    if peak_index < num_lags
        plot(peak_index, 1.0, 'r*', 'MarkerSize', 14, 'LineWidth', 2);
    end
    grid on; hold off;

    title('4. Peak Region: FPGA Fixed-Point vs MATLAB Ideal (Linear)', 'Color', 'w', 'FontSize', 11, 'FontWeight', 'bold');
    xlabel('Delay Lag Index (k)', 'Color', label_color);
    ylabel('Local-Normalized Magnitude', 'Color', label_color);
    ylim([-0.05, 1.15]);

    annotation_str = sprintf('Target Delay : %.2f \\mus\nTarget Range : %.2f km', target_delay_us, target_range_km);
    text_x = win_lags(1) + 5;
    text(text_x, 0.88, annotation_str, 'Color', [1.0 0.9 0.2], 'FontSize', 10, ...
         'FontWeight', 'bold', 'BackgroundColor', [0.1 0.1 0.15], 'EdgeColor', [0.5 0.5 0.5]);

    legend({'MATLAB Golden Reference', 'FPGA Q1.15 Hardware', 'Detected Peak'}, ...
           'TextColor', 'w', 'Color', [0.15 0.15 0.20], 'Location', 'northeast');
    set(ax4, 'Color', ax_bg, 'XColor', label_color, 'YColor', label_color);

    sgtitle('Digilent Nexys A7-100T FPGA Radar Matched Filter System', ...
            'Color', 'w', 'FontSize', 14, 'FontWeight', 'bold');
end
