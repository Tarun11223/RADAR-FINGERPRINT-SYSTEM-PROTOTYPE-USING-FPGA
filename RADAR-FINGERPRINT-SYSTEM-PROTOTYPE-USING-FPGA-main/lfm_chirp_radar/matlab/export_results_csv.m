% =========================================================================
% Script Name  : export_results_csv.m
% Project      : FPGA Radar Matched Filter (Cross-Correlation)
% Target FPGA  : Digilent Nexys A7-100T (Artix-7 XC7A100T)
% Description  : Exports ALL radar matched filter results into a single
%                combined CSV file: radar_results_combined.csv
%
%                Columns (NaN-padded where array is shorter):
%                  RowIndex
%                  --- Tx Chirp (2119 rows) ---
%                  Tx_SampleIndex, Tx_Time_us, Tx_Real, Tx_Imag, Tx_Magnitude
%                  --- Rx Echo  (19071 rows) ---
%                  Rx_SampleIndex, Rx_Time_us, Rx_Real, Rx_Imag, Rx_Magnitude
%                  --- FPGA Q1.15 Correlation (16953 rows) ---
%                  Lag_Index, Lag_Delay_us, Lag_Range_km,
%                  FPGA_Corr_Real, FPGA_Corr_Imag, FPGA_Magnitude,
%                  FPGA_Norm_Mag, FPGA_Norm_dB
%                  --- MATLAB Float64 Golden Reference (16953 rows) ---
%                  MATLAB_Corr_Real, MATLAB_Corr_Imag, MATLAB_Magnitude,
%                  MATLAB_Norm_Mag, MATLAB_Norm_dB
%                  --- Summary Metrics (row 1 only) ---
%                  Peak_Lag, Target_Delay_us, Target_Range_km,
%                  NMSE_Peak_Region, CrossCorr_Coef, MatchPercent
%
% Usage:
%   Run main.m first, then:
%       >> main
%       >> export_results_csv
%   OR standalone (recomputes from CSVs):
%       >> export_results_csv
%
% Output: e:\xilinxprojects\radar_cross_corelation\simple_radar_results_combined.csv
% =========================================================================

fprintf('=====================================================\n');
fprintf('  FPGA Radar Matched Filter — Single CSV Export    \n');
fprintf('=====================================================\n\n');

% Output directory = same folder as this script
output_dir = fileparts(mfilename('fullpath'));
if isempty(output_dir), output_dir = pwd; end
out_file = fullfile(output_dir, 'simple_radar_results_combined.csv');
fprintf('[INFO] Output file:\n       %s\n\n', out_file);

% -------------------------------------------------------------------------
% System Parameters
% -------------------------------------------------------------------------
FS      = 100e6;
C_SPEED = 3e8;
Ts      = 1 / FS;
N_TX    = 2119;
N_RX    = 19071;
TOTAL_LAGS = N_RX - N_TX + 1;  % 16953

% -------------------------------------------------------------------------
% Load / Reuse Workspace Variables
% -------------------------------------------------------------------------
need_tx   = ~exist('tx_complex',   'var') || isempty(tx_complex);
need_rx   = ~exist('rx_complex',   'var') || isempty(rx_complex);
need_fpga = ~exist('fpga_corr',    'var') || isempty(fpga_corr);
need_mat  = ~exist('matlab_corr',  'var') || isempty(matlab_corr);
need_peak = ~exist('fpga_peak_lag','var');

% *** Length validation: workspace variables may be from simple_main (wrong sizes) ***
if ~need_tx  && length(tx_complex) ~= N_TX
    fprintf('[WARNING] tx_complex in workspace has %d samples (expected %d). Reloading from CSV.\n', length(tx_complex), N_TX);
    need_tx = true;
end
if ~need_rx  && length(rx_complex) ~= N_RX
    fprintf('[WARNING] rx_complex in workspace has %d samples (expected %d). Reloading from CSV.\n', length(rx_complex), N_RX);
    need_rx  = true;
    need_mat = true;   % must recompute if Rx changes
    need_fpga = true;
    need_peak = true;
end
if ~need_fpga && length(fpga_corr) ~= TOTAL_LAGS
    fprintf('[WARNING] fpga_corr in workspace has %d lags (expected %d). Will use MATLAB simulation.\n', length(fpga_corr), TOTAL_LAGS);
    need_fpga = true;
    need_peak = true;
end
if ~need_mat && length(matlab_corr) ~= TOTAL_LAGS
    fprintf('[WARNING] matlab_corr in workspace has %d lags (expected %d). Recomputing.\n', length(matlab_corr), TOTAL_LAGS);
    need_mat = true;
end


if need_tx || need_rx
    fprintf('[INFO] Loading Tx/Rx signals from CSV...\n');
    tx_tbl    = readtable(fullfile(output_dir, 'LFM_Chirp_Tx_data.csv'));
    rx_tbl    = readtable(fullfile(output_dir, 'LFM_Chirp_Rx_Data.csv'));
    tx_complex = tx_tbl.Real + 1j * tx_tbl.Imag;
    rx_complex = rx_tbl.Real + 1j * rx_tbl.Imag;
end

if need_mat
    fprintf('[INFO] Computing MATLAB golden reference (~30s)...\n');
    matlab_corr = zeros(TOTAL_LAGS, 1);
    for k = 1:TOTAL_LAGS
        matlab_corr(k) = sum(rx_complex(k:k+N_TX-1) .* conj(tx_complex));
    end
end

if need_fpga
    fprintf('[WARNING] fpga_corr not in workspace. Using MATLAB simulation.\n');
    fpga_corr = matlab_corr / N_TX;
    is_hw = false;
else
    if ~exist('is_hw','var'), is_hw = true; end
end

if need_peak
    [~, pi1] = max(abs(fpga_corr));
    fpga_peak_lag = pi1 - 1;
end

% -------------------------------------------------------------------------
% Compute Metrics
% -------------------------------------------------------------------------
min_len    = min(length(fpga_corr), length(matlab_corr));
fp_trim    = fpga_corr(1:min_len);
ml_trim    = matlab_corr(1:min_len);

max_fp = max(abs(fp_trim));  if max_fp == 0, max_fp = 1; end
max_ml = max(abs(ml_trim));  if max_ml == 0, max_ml = 1; end

fpga_norm  = abs(fp_trim) / max_fp;
matlab_norm = abs(ml_trim) / max_ml;
fpga_dB    = max(20*log10(fpga_norm  + 1e-10), -60);
matlab_dB  = max(20*log10(matlab_norm + 1e-10), -60);

% Peak-region NMSE & correlation (±250 lags)
pk      = fpga_peak_lag + 1;
w       = 250;
p_s     = max(1,       pk - w);
p_e     = min(min_len, pk + w);
nmse    = mean((matlab_norm(p_s:p_e) - fpga_norm(p_s:p_e)).^2) / mean(matlab_norm(p_s:p_e).^2);
cm      = corrcoef(matlab_norm(p_s:p_e), fpga_norm(p_s:p_e));
corr_c  = cm(1,2);

target_delay_us = fpga_peak_lag * Ts * 1e6;
target_range_km = (C_SPEED * fpga_peak_lag * Ts) / 2 / 1000;

% -------------------------------------------------------------------------
% Build Combined Table — all arrays padded to N_RX rows with NaN
% -------------------------------------------------------------------------
N = N_RX;  % longest array = 19071 rows

nan_col = @(n) nan(N, 1);

% --- Row Index ---
RowIndex = (1:N)';

% --- Tx Chirp (2119 rows, rest NaN) ---
tx_idx = nan_col(); tx_t = nan_col();
tx_re  = nan_col(); tx_im = nan_col(); tx_mag = nan_col();
tx_idx(1:N_TX) = (0:N_TX-1)';
tx_t(1:N_TX)   = (0:N_TX-1)' * Ts * 1e6;
tx_re(1:N_TX)  = real(tx_complex);
tx_im(1:N_TX)  = imag(tx_complex);
tx_mag(1:N_TX) = abs(tx_complex);

% --- Rx Echo (19071 rows, all filled) ---
rx_idx = (0:N_RX-1)';
rx_t   = rx_idx * Ts * 1e6;
rx_re  = real(rx_complex);
rx_im  = imag(rx_complex);
rx_mag = abs(rx_complex);

% --- FPGA Correlation (16953 rows, rest NaN) ---
lag_i = nan_col(); lag_t = nan_col(); lag_r = nan_col();
fp_re = nan_col(); fp_im = nan_col(); fp_m  = nan_col();
fp_n  = nan_col(); fp_db = nan_col();
lag_i(1:min_len) = (0:min_len-1)';
lag_t(1:min_len) = (0:min_len-1)' * Ts * 1e6;
lag_r(1:min_len) = (C_SPEED * (0:min_len-1)' * Ts) / 2 / 1000;
fp_re(1:min_len) = real(fp_trim);
fp_im(1:min_len) = imag(fp_trim);
fp_m(1:min_len)  = abs(fp_trim);
fp_n(1:min_len)  = fpga_norm;
fp_db(1:min_len) = fpga_dB;

% --- MATLAB Golden Reference (16953 rows, rest NaN) ---
ml_re = nan_col(); ml_im = nan_col(); ml_m  = nan_col();
ml_n  = nan_col(); ml_db = nan_col();
ml_re(1:min_len) = real(ml_trim);
ml_im(1:min_len) = imag(ml_trim);
ml_m(1:min_len)  = abs(ml_trim);
ml_n(1:min_len)  = matlab_norm;
ml_db(1:min_len) = matlab_dB;

% --- Summary Metrics (row 1 only, rest NaN) ---
sum_peak   = nan_col(); sum_peak(1)   = fpga_peak_lag;
sum_delay  = nan_col(); sum_delay(1)  = target_delay_us;
sum_range  = nan_col(); sum_range(1)  = target_range_km;
sum_nmse   = nan_col(); sum_nmse(1)   = nmse;
sum_corr   = nan_col(); sum_corr(1)   = corr_c;
sum_match  = nan_col(); sum_match(1)  = corr_c * 100;

% -------------------------------------------------------------------------
% Assemble and Write Single Combined Table
% -------------------------------------------------------------------------
fprintf('[INFO] Assembling combined table (%d rows x 32 columns)...\n', N);

T = table( ...
    RowIndex, ...
    tx_idx,  tx_t,   tx_re,  tx_im,  tx_mag,  ...
    rx_idx,  rx_t,   rx_re,  rx_im,  rx_mag,  ...
    lag_i,   lag_t,  lag_r,  ...
    fp_re,   fp_im,  fp_m,   fp_n,   fp_db,   ...
    ml_re,   ml_im,  ml_m,   ml_n,   ml_db,   ...
    sum_peak, sum_delay, sum_range, sum_nmse, sum_corr, sum_match, ...
    'VariableNames', { ...
        'RowIndex', ...
        'Tx_SampleIndex', 'Tx_Time_us',   'Tx_Real',  'Tx_Imag',  'Tx_Magnitude', ...
        'Rx_SampleIndex', 'Rx_Time_us',   'Rx_Real',  'Rx_Imag',  'Rx_Magnitude', ...
        'Lag_Index',      'Lag_Delay_us', 'Lag_Range_km', ...
        'FPGA_Corr_Real', 'FPGA_Corr_Imag', 'FPGA_Magnitude', 'FPGA_Norm_Mag', 'FPGA_Norm_dB', ...
        'MATLAB_Corr_Real','MATLAB_Corr_Imag','MATLAB_Magnitude','MATLAB_Norm_Mag','MATLAB_Norm_dB', ...
        'Peak_Lag', 'Target_Delay_us', 'Target_Range_km', 'NMSE_Peak_Region', 'CrossCorr_Coef', 'Match_Percent' ...
    });

fprintf('[EXPORT] Writing radar_results_combined.csv...\n');
writetable(T, out_file);

% -------------------------------------------------------------------------
% Summary
% -------------------------------------------------------------------------
finfo = dir(out_file);
fprintf('\n=====================================================\n');
fprintf('  EXPORT COMPLETE\n');
fprintf('=====================================================\n');
fprintf('  File  : simple_radar_results_combined.csv\n');
fprintf('  Rows  : %d\n', N);
fprintf('  Cols  : 30\n');
fprintf('  Size  : %.2f MB\n', finfo.bytes / 1e6);
fprintf('  Path  : %s\n', out_file);
fprintf('-----------------------------------------------------\n');
fprintf('  FPGA Peak Lag    : %d samples\n',    fpga_peak_lag);
fprintf('  Target Range     : %.4f km\n',        target_range_km);
fprintf('  Cross-Corr (peak): %.4f (%.2f%%)\n',  corr_c, corr_c*100);
fprintf('=====================================================\n\n');
fprintf('  Column Groups in CSV:\n');
fprintf('  [1]        RowIndex\n');
fprintf('  [2-6]      Tx_SampleIndex, Tx_Time_us, Tx_Real, Tx_Imag, Tx_Magnitude\n');
fprintf('             (rows 1-%d filled, %d-%d = NaN)\n', N_TX, N_TX+1, N);
fprintf('  [7-11]     Rx_SampleIndex, Rx_Time_us, Rx_Real, Rx_Imag, Rx_Magnitude\n');
fprintf('             (all %d rows filled)\n', N_RX);
fprintf('  [12-14]    Lag_Index, Lag_Delay_us, Lag_Range_km\n');
fprintf('  [15-19]    FPGA_Corr_Real/Imag, FPGA_Magnitude, FPGA_Norm_Mag, FPGA_Norm_dB\n');
fprintf('             (rows 1-%d filled, %d-%d = NaN)\n', min_len, min_len+1, N);
fprintf('  [20-24]    MATLAB_Corr_Real/Imag, MATLAB_Magnitude, MATLAB_Norm_Mag, MATLAB_Norm_dB\n');
fprintf('  [25-30]    Peak_Lag, Target_Delay_us, Target_Range_km,\n');
fprintf('             NMSE_Peak_Region, CrossCorr_Coef, Match_Percent\n');
fprintf('             (row 1 only, rest = NaN)\n');
fprintf('=====================================================\n');
