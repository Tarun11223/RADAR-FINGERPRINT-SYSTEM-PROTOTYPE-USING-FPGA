% =========================================================================
% Script Name  : simple_export_csv.m
% Project      : Simple Rectangular Pulse Cross-Correlation on FPGA
% Description  : Standalone CSV exporter for the simple rectangular pulse
%                cross-correlation example. Completely independent from the
%                LFM chirp radar project.
%
%                Generates: simple_radar_results_combined.csv
%
%                Tx = [250 zeros + 1000 ones]   N_TX = 1250
%                Rx = [500 zeros + 1000 ones]   N_RX = 1500
%                Lags                           TOTAL_LAGS = 251
%                Expected Peak at k = 250       Range = 375 m
%
% Usage:
%   >> cd('E:\xilinxprojects\radar_cross_corelation\simple_example')
%   >> simple_main           % run first (populates workspace with FPGA data)
%   >> simple_export_csv     % generates CSV
%   OR standalone (no FPGA needed):
%   >> simple_export_csv
% =========================================================================

clear_local = false; % do not clear base workspace

fprintf('=====================================================\n');
fprintf('  Simple Pulse Cross-Correlation — CSV Exporter    \n');
fprintf('=====================================================\n\n');

% -------------------------------------------------------------------------
% Parameters — simple example ONLY (not LFM chirp)
% -------------------------------------------------------------------------
FS          = 100e6;
C_SPEED     = 3e8;
Ts          = 1 / FS;
N_ZEROS_TX  = 250;
N_ONES_TX   = 1000;
N_ZEROS_RX  = 500;
N_ONES_RX   = 1000;
N_TX        = N_ZEROS_TX + N_ONES_TX;   % 1250
N_RX        = N_ZEROS_RX + N_ONES_RX;  % 1500
TOTAL_LAGS  = N_RX - N_TX + 1;         % 251
EXPECTED_PEAK = N_ZEROS_RX - N_ZEROS_TX; % 250

% Output file — save in same folder as this script
out_dir  = fileparts(mfilename('fullpath'));
if isempty(out_dir), out_dir = pwd; end
out_file = fullfile(out_dir, 'simple_radar_results_combined.csv');
fprintf('[INFO] Output: %s\n\n', out_file);

% -------------------------------------------------------------------------
% Step 1: Build Tx and Rx signals from scratch (ignore workspace)
%         Always recompute — don't risk picking up LFM chirp data
% -------------------------------------------------------------------------
fprintf('[INFO] Building Tx and Rx rectangular pulse signals...\n');
tx_sig = [zeros(N_ZEROS_TX, 1); ones(N_ONES_TX, 1)];   % 1250 samples
rx_sig = [zeros(N_ZEROS_RX, 1); ones(N_ONES_RX, 1)];   % 1500 samples
fprintf('       Tx = [%d zeros + %d ones]  length=%d\n', N_ZEROS_TX, N_ONES_TX, N_TX);
fprintf('       Rx = [%d zeros + %d ones]  length=%d\n', N_ZEROS_RX, N_ONES_RX, N_RX);

% -------------------------------------------------------------------------
% Step 2: MATLAB golden reference cross-correlation
% -------------------------------------------------------------------------
fprintf('[INFO] Computing MATLAB golden cross-correlation (%d lags)...\n', TOTAL_LAGS);
matlab_corr = zeros(TOTAL_LAGS, 1);
for k = 1:TOTAL_LAGS
    matlab_corr(k) = sum(rx_sig(k:k+N_TX-1) .* conj(tx_sig));
end
[~, ml_peak_idx] = max(abs(matlab_corr));
matlab_peak_lag = ml_peak_idx - 1;
fprintf('       MATLAB Peak at k = %d\n', matlab_peak_lag);

% -------------------------------------------------------------------------
% Step 3: Use FPGA data from workspace if valid, else use MATLAB simulation
% -------------------------------------------------------------------------
use_hw = false;
if exist('fpga_corr','var') && ~isempty(fpga_corr) && length(fpga_corr) == TOTAL_LAGS
    fprintf('[INFO] Using FPGA hardware data from workspace (length=%d).\n', length(fpga_corr));
    fpga_data = fpga_corr(:);
    use_hw = true;
else
    fprintf('[INFO] No matching FPGA data in workspace — using MATLAB simulation.\n');
    % Simulate Q1.15 FPGA output: normalize and quantize to 16-bit
    fpga_data = matlab_corr / N_TX;  % approximate scaling
end

if exist('fpga_peak_lag','var') && isscalar(fpga_peak_lag) && ...
   fpga_peak_lag >= 0 && fpga_peak_lag < TOTAL_LAGS
    peak_lag = fpga_peak_lag;
else
    [~, pk_idx] = max(abs(fpga_data));
    peak_lag = pk_idx - 1;
end

% -------------------------------------------------------------------------
% Step 4: Compute metrics
% -------------------------------------------------------------------------
min_len    = min(length(fpga_data), length(matlab_corr));
fp_trim    = fpga_data(1:min_len);
ml_trim    = matlab_corr(1:min_len);

max_fp = max(abs(fp_trim));  if max_fp == 0, max_fp = 1; end
max_ml = max(abs(ml_trim));  if max_ml == 0, max_ml = 1; end

fpga_norm   = abs(fp_trim)  / max_fp;
matlab_norm = abs(ml_trim) / max_ml;
fpga_dB     = max(20*log10(fpga_norm   + 1e-10), -60);
matlab_dB   = max(20*log10(matlab_norm + 1e-10), -60);

% Peak-region accuracy (±50 lags)
pk      = peak_lag + 1;
w       = min(50, pk - 1);
p_s     = max(1, pk - w);
p_e     = min(min_len, pk + w);
nmse    = mean((matlab_norm(p_s:p_e) - fpga_norm(p_s:p_e)).^2) / mean(matlab_norm(p_s:p_e).^2);
cm      = corrcoef(matlab_norm(p_s:p_e), fpga_norm(p_s:p_e));
corr_c  = cm(1, 2);

target_delay_us  = peak_lag * Ts * 1e6;
target_range_m   = (C_SPEED * peak_lag * Ts) / 2;
target_range_km  = target_range_m / 1000;

% -------------------------------------------------------------------------
% Step 5: Build combined table — padded to N_RX rows (1500)
% -------------------------------------------------------------------------
N = N_RX;  % 1500 rows total (longest signal)
fprintf('[INFO] Building combined table (%d rows x 29 columns)...\n', N);

nan_col = @() nan(N, 1);

% Row index
RowIndex = (1:N)';

% --- Tx Signal (1250 rows, rest NaN) ---
Tx_SampleIndex = nan_col(); Tx_Time_us  = nan_col();
Tx_Real        = nan_col(); Tx_Imag     = nan_col(); Tx_Magnitude = nan_col();
Tx_SampleIndex(1:N_TX) = (0:N_TX-1)';
Tx_Time_us(1:N_TX)     = (0:N_TX-1)' * Ts * 1e6;
Tx_Real(1:N_TX)        = real(tx_sig);
Tx_Imag(1:N_TX)        = imag(tx_sig);
Tx_Magnitude(1:N_TX)   = abs(tx_sig);

% --- Rx Signal (1500 rows, all filled) ---
Rx_SampleIndex = (0:N_RX-1)';
Rx_Time_us     = Rx_SampleIndex * Ts * 1e6;
Rx_Real        = real(rx_sig);
Rx_Imag        = imag(rx_sig);
Rx_Magnitude   = abs(rx_sig);

% --- Correlation lags (251 rows, rest NaN) ---
Lag_Index    = nan_col(); Lag_Delay_us = nan_col(); Lag_Range_m = nan_col();
Lag_Index(1:min_len)    = (0:min_len-1)';
Lag_Delay_us(1:min_len) = (0:min_len-1)' * Ts * 1e6;
Lag_Range_m(1:min_len)  = (C_SPEED * (0:min_len-1)' * Ts) / 2;

% --- FPGA Correlation (251 rows, rest NaN) ---
FPGA_Corr_Real = nan_col(); FPGA_Corr_Imag = nan_col();
FPGA_Magnitude = nan_col(); FPGA_Norm_Mag  = nan_col(); FPGA_Norm_dB = nan_col();
FPGA_Corr_Real(1:min_len) = real(fp_trim);
FPGA_Corr_Imag(1:min_len) = imag(fp_trim);
FPGA_Magnitude(1:min_len) = abs(fp_trim);
FPGA_Norm_Mag(1:min_len)  = fpga_norm;
FPGA_Norm_dB(1:min_len)   = fpga_dB;

% --- MATLAB Golden Reference (251 rows, rest NaN) ---
MATLAB_Corr_Real = nan_col(); MATLAB_Corr_Imag = nan_col();
MATLAB_Magnitude = nan_col(); MATLAB_Norm_Mag  = nan_col(); MATLAB_Norm_dB = nan_col();
MATLAB_Corr_Real(1:min_len) = real(ml_trim);
MATLAB_Corr_Imag(1:min_len) = imag(ml_trim);
MATLAB_Magnitude(1:min_len) = abs(ml_trim);
MATLAB_Norm_Mag(1:min_len)  = matlab_norm;
MATLAB_Norm_dB(1:min_len)   = matlab_dB;

% --- Summary metrics (row 1 only) ---
Exec_Source     = nan_col(); Exec_Source(1)     = double(use_hw);
Tx_Zeros        = nan_col(); Tx_Zeros(1)        = N_ZEROS_TX;
Tx_Ones         = nan_col(); Tx_Ones(1)         = N_ONES_TX;
Rx_Zeros        = nan_col(); Rx_Zeros(1)        = N_ZEROS_RX;
Rx_Ones         = nan_col(); Rx_Ones(1)         = N_ONES_RX;
Expected_Peak   = nan_col(); Expected_Peak(1)   = EXPECTED_PEAK;
FPGA_Peak_Lag   = nan_col(); FPGA_Peak_Lag(1)   = peak_lag;
MATLAB_Peak_Lag = nan_col(); MATLAB_Peak_Lag(1) = matlab_peak_lag;
Target_Delay_us = nan_col(); Target_Delay_us(1) = target_delay_us;
Target_Range_m  = nan_col(); Target_Range_m(1)  = target_range_m;
Target_Range_km = nan_col(); Target_Range_km(1) = target_range_km;
NMSE            = nan_col(); NMSE(1)            = nmse;
CrossCorr_Coef  = nan_col(); CrossCorr_Coef(1)  = corr_c;
Match_Percent   = nan_col(); Match_Percent(1)   = corr_c * 100;

% -------------------------------------------------------------------------
% Step 6: Assemble and Write
% -------------------------------------------------------------------------
T = table( ...
    RowIndex, ...
    Tx_SampleIndex, Tx_Time_us, Tx_Real, Tx_Imag, Tx_Magnitude, ...
    Rx_SampleIndex, Rx_Time_us, Rx_Real, Rx_Imag, Rx_Magnitude, ...
    Lag_Index, Lag_Delay_us, Lag_Range_m, ...
    FPGA_Corr_Real, FPGA_Corr_Imag, FPGA_Magnitude, FPGA_Norm_Mag, FPGA_Norm_dB, ...
    MATLAB_Corr_Real, MATLAB_Corr_Imag, MATLAB_Magnitude, MATLAB_Norm_Mag, MATLAB_Norm_dB, ...
    Exec_Source, Tx_Zeros, Tx_Ones, Rx_Zeros, Rx_Ones, ...
    Expected_Peak, FPGA_Peak_Lag, MATLAB_Peak_Lag, ...
    Target_Delay_us, Target_Range_m, Target_Range_km, ...
    NMSE, CrossCorr_Coef, Match_Percent);

fprintf('[EXPORT] Writing CSV...\n');
writetable(T, out_file);

% -------------------------------------------------------------------------
% Step 7: Summary
% -------------------------------------------------------------------------
finfo = dir(out_file);
fprintf('\n=====================================================\n');
fprintf('  SIMPLE EXAMPLE CSV EXPORT COMPLETE               \n');
fprintf('=====================================================\n');
fprintf('  File      : simple_radar_results_combined.csv\n');
fprintf('  Location  : %s\n', out_dir);
fprintf('  Rows      : %d  (padded to N_RX=%d)\n', N, N_RX);
fprintf('  Cols      : %d\n', width(T));
fprintf('  Size      : %.3f MB\n', finfo.bytes / 1e6);
fprintf('-----------------------------------------------------\n');
fprintf('  Tx Signal : [%d zeros + %d ones]  N_TX=%d\n', N_ZEROS_TX, N_ONES_TX, N_TX);
fprintf('  Rx Signal : [%d zeros + %d ones]  N_RX=%d\n', N_ZEROS_RX, N_ONES_RX, N_RX);
fprintf('  Lags      : %d\n', TOTAL_LAGS);
if use_hw
    src_str = 'Physical FPGA Hardware';
else
    src_str = 'MATLAB Software Simulation';
end
fprintf('  Source    : %s\n', src_str);

fprintf('-----------------------------------------------------\n');
fprintf('  Expected Peak : k = %d samples\n',     EXPECTED_PEAK);
fprintf('  FPGA Peak     : k = %d samples\n',     peak_lag);
fprintf('  MATLAB Peak   : k = %d samples\n',     matlab_peak_lag);
fprintf('  Target Delay  : %.2f µs\n',            target_delay_us);
fprintf('  Target Range  : %.1f m  (%.4f km)\n',  target_range_m, target_range_km);
fprintf('  NMSE          : %.4e\n',               nmse);
fprintf('  Match %%        : %.2f%%\n',             corr_c * 100);
fprintf('=====================================================\n');
fprintf('  Column Layout:\n');
fprintf('  [1]      RowIndex\n');
fprintf('  [2-6]    Tx: SampleIndex, Time_us, Real, Imag, Magnitude  (rows 1-%d)\n', N_TX);
fprintf('  [7-11]   Rx: SampleIndex, Time_us, Real, Imag, Magnitude  (rows 1-%d)\n', N_RX);
fprintf('  [12-14]  Lag: Index, Delay_us, Range_m  (rows 1-%d)\n', min_len);
fprintf('  [15-19]  FPGA: Corr_Real, Corr_Imag, Magnitude, Norm_Mag, Norm_dB\n');
fprintf('  [20-24]  MATLAB: Corr_Real, Corr_Imag, Magnitude, Norm_Mag, Norm_dB\n');
fprintf('  [25-38]  Summary metrics  (row 1 only, rest = NaN)\n');
fprintf('=====================================================\n');
