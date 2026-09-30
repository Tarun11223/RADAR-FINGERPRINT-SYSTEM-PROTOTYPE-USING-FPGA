function simple_plot_results(tx_signal, rx_signal, fpga_corr, matlab_corr, ...
                              peak_index, fs, c, ...
                              n_zeros_tx, n_ones_tx, n_zeros_rx, n_ones_rx)
% =========================================================================
% Function Name  : simple_plot_results
% Project        : Simple Rectangular Pulse Cross-Correlation on FPGA
% Description    : 4-panel visualization for the simple rectangular
%                  pulse cross-correlation theory example.
% =========================================================================

    if nargin < 6, fs = 100e6; end
    if nargin < 7, c  = 3e8;   end

    Ts       = 1 / fs;
    num_tx   = length(tx_signal);
    num_rx   = length(rx_signal);
    num_lags = min(length(fpga_corr), length(matlab_corr));

    target_delay_us = peak_index * Ts * 1e6;
    target_range_m  = (c * peak_index * Ts) / 2;

    % Normalize
    fpga_norm   = abs(fpga_corr(1:num_lags))   / max(abs(fpga_corr));
    matlab_norm = abs(matlab_corr(1:num_lags)) / max(abs(matlab_corr));

    lags    = 0:num_lags-1;
    t_tx_us = (0:num_tx-1) * Ts * 1e6;
    t_rx_us = (0:num_rx-1) * Ts * 1e6;

    bg_col   = [0.07 0.08 0.11];
    ax_col   = [0.11 0.12 0.16];
    lbl_col  = [0.85 0.87 0.90];

    figure('Name','Simple Rectangular Pulse Cross-Correlation — FPGA Demo', ...
           'NumberTitle','off','Color',bg_col,'Position',[80 80 1280 820]);

    % -----------------------------------------------------------------------
    % Subplot 1: Tx Signal
    % -----------------------------------------------------------------------
    ax1 = subplot(2,2,1);
    plot(t_tx_us, real(tx_signal), 'LineWidth', 2.0, 'Color', [0.25 0.75 1.0]); hold on;
    xline(n_zeros_tx * Ts * 1e6, '--', 'Color', [1 0.6 0.2], 'LineWidth', 1.5);
    yline(0.5, ':', 'Color', [0.6 0.6 0.6], 'LineWidth', 1.0);
    text(n_zeros_tx * Ts * 1e6 + 0.2, 0.55, sprintf('Onset\nk=%d', n_zeros_tx), ...
         'Color',[1 0.7 0.2],'FontSize',9,'FontWeight','bold');
    hold off; grid on;
    title(sprintf('1. Tx Signal: [%d zeros + %d ones]', n_zeros_tx, n_ones_tx), ...
          'Color','w','FontSize',11,'FontWeight','bold');
    xlabel('Time (µs)','Color',lbl_col); ylabel('Amplitude','Color',lbl_col);
    ylim([-0.2, 1.4]);
    set(ax1,'Color',ax_col,'XColor',lbl_col,'YColor',lbl_col,'GridColor',[0.3 0.3 0.35]);

    % -----------------------------------------------------------------------
    % Subplot 2: Rx Signal
    % -----------------------------------------------------------------------
    ax2 = subplot(2,2,2);
    plot(t_rx_us, real(rx_signal), 'LineWidth', 2.0, 'Color', [0.3 0.92 0.45]); hold on;
    xline(n_zeros_rx * Ts * 1e6, '--', 'Color', [1 0.4 0.4], 'LineWidth', 1.5);
    yline(0.5, ':', 'Color', [0.6 0.6 0.6], 'LineWidth', 1.0);
    text(n_zeros_rx * Ts * 1e6 + 0.2, 0.55, sprintf('Onset\nk=%d', n_zeros_rx), ...
         'Color',[1 0.5 0.5],'FontSize',9,'FontWeight','bold');
    hold off; grid on;
    title(sprintf('2. Rx Signal: [%d zeros + %d ones]', n_zeros_rx, n_ones_rx), ...
          'Color','w','FontSize',11,'FontWeight','bold');
    xlabel('Time (µs)','Color',lbl_col); ylabel('Amplitude','Color',lbl_col);
    ylim([-0.2, 1.4]);
    set(ax2,'Color',ax_col,'XColor',lbl_col,'YColor',lbl_col,'GridColor',[0.3 0.3 0.35]);

    % -----------------------------------------------------------------------
    % Subplot 3: Full Cross-Correlation Profile (both MATLAB & FPGA)
    % -----------------------------------------------------------------------
    ax3 = subplot(2,2,3);
    plot(lags, matlab_norm, 'w--', 'LineWidth', 2.0); hold on;
    plot(lags, fpga_norm,   'Color', [0.9 0.25 0.9], 'LineWidth', 1.8);
    if peak_index < num_lags
        plot(peak_index, fpga_norm(peak_index+1), 'r^', ...
             'MarkerSize', 10, 'LineWidth', 2, 'MarkerFaceColor','r');
        xline(peak_index, ':', 'Color', [1 0.6 0.2], 'LineWidth', 1.2);
    end
    hold off; grid on;
    title('3. Cross-Correlation Profile R(k)', 'Color','w','FontSize',11,'FontWeight','bold');
    xlabel('Lag Index k','Color',lbl_col); ylabel('Normalized Magnitude','Color',lbl_col);
    ylim([-0.05, 1.15]);
    legend({'MATLAB Float64 Reference', 'FPGA Q1.15 Hardware', sprintf('Peak @ k=%d', peak_index)}, ...
           'TextColor','w','Color',[0.14 0.15 0.20],'Location','northwest');
    set(ax3,'Color',ax_col,'XColor',lbl_col,'YColor',lbl_col,'GridColor',[0.3 0.3 0.35]);

    % -----------------------------------------------------------------------
    % Subplot 4: Theory Explanation Annotation Panel
    % -----------------------------------------------------------------------
    ax4 = subplot(2,2,4);
    plot(lags, matlab_norm, 'w--', 'LineWidth', 2.5); hold on;
    plot(lags, fpga_norm,   'Color', [0.0 0.9 0.8], 'LineWidth', 1.8);
    if peak_index < num_lags
        plot(peak_index, 1.0, 'r*', 'MarkerSize', 16, 'LineWidth', 2.5);
    end

    % Shade rising and falling edges
    fill([0, peak_index, peak_index, 0], [0, 0, 1, 0.0], ...
         [0.3 0.6 0.3], 'FaceAlpha', 0.12, 'EdgeColor','none');

    hold off; grid on;

    % Annotations
    text(5, 0.85, sprintf(['\\bf Theory:\\rm\n' ...
        'Tx onset: k = %d\n' ...
        'Rx onset: k = %d\n\n' ...
        '\\bf Peak at:\\rm\n' ...
        'k = %d - %d = \\bf%d\\rm\n\n' ...
        'Delay  = %d × 10 ns = \\bf%.1f µs\\rm\n' ...
        'Range  = \\bf%.0f m (%.3f km)\\rm'], ...
        n_zeros_tx, n_zeros_rx, ...
        n_zeros_rx, n_zeros_tx, peak_index, ...
        peak_index, target_delay_us, ...
        target_range_m, target_range_m/1000), ...
        'Color', [1.0 0.95 0.7], 'FontSize', 10, ...
        'BackgroundColor', [0.10 0.11 0.16], ...
        'EdgeColor', [0.5 0.5 0.6]);

    title('4. Peak Region + Theory Explanation', 'Color','w','FontSize',11,'FontWeight','bold');
    xlabel('Lag Index k','Color',lbl_col); ylabel('Local Normalized Magnitude','Color',lbl_col);
    ylim([-0.05, 1.20]);
    legend({'MATLAB Reference', 'FPGA Q1.15', 'Detected Peak'}, ...
           'TextColor','w','Color',[0.14 0.15 0.20],'Location','southeast');
    set(ax4,'Color',ax_col,'XColor',lbl_col,'YColor',lbl_col,'GridColor',[0.3 0.3 0.35]);

    sgtitle({'Rectangular Pulse Cross-Correlation — Nexys A7 FPGA Demo', ...
             sprintf('Tx=[%dz+%d1s]  Rx=[%dz+%d1s]  →  Peak at k=%d  |  Range: %.0f m', ...
                     n_zeros_tx, n_ones_tx, n_zeros_rx, n_ones_rx, peak_index, target_range_m)}, ...
            'Color','w','FontSize',13,'FontWeight','bold');
end
