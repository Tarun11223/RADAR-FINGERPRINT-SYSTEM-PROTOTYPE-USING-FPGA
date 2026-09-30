function make_mem()
% =========================================================================
% Function Name : make_mem
% Project       : FPGA Radar Matched Filter (Cross-Correlation)
% Description   : Reads "LFM_Chirp_Tx_data.csv", converts complex IQ data
%                 to 16-bit signed Q1.15 fixed-point format, and generates
%                 formatted hexadecimal memory initialization file "tx.mem".
% =========================================================================

    fprintf('=====================================================\n');
    fprintf('  MATLAB Q1.15 Memory Generator for Transmit Chirp  \n');
    fprintf('=====================================================\n');

    script_dir = fileparts(mfilename('fullpath'));
    data_dir   = fullfile(script_dir, '..', 'data');
    csv_file   = fullfile(data_dir, 'LFM_Chirp_Tx_data.csv');
    mem_file   = fullfile(data_dir, 'tx.mem');

    if ~exist(csv_file, 'file')
        error('File %s does not exist! Please generate CSV data first.', csv_file);
    end

    % Read CSV File
    opts = detectImportOptions(csv_file);
    tx_data = readtable(csv_file, opts);

    tx_real_raw = tx_data.Real;
    tx_imag_raw = tx_data.Imag;
    num_samples = length(tx_real_raw);

    fprintf('Successfully read %d complex Tx samples from %s\n', num_samples, csv_file);

    % Q1.15 Fixed-Point Conversion (Scale by 2^15 = 32768)
    % Clamp values to [-1.0, 0.99996948]
    tx_real_clamped = max(-1.0, min(0.99996948, tx_real_raw));
    tx_imag_clamped = max(-1.0, min(0.99996948, tx_imag_raw));

    tx_real_q15 = int16(round(tx_real_clamped * 32768));
    tx_imag_q15 = int16(round(tx_imag_clamped * 32768));

    % Convert 16-bit signed integers to 4-character Hex strings (Two's Complement)
    fid = fopen(mem_file, 'w');
    if fid == -1
        error('Cannot open %s for writing!', mem_file);
    end

    for i = 1:num_samples
        % Format: Upper 16 bits = Real (I), Lower 16 bits = Imag (Q)
        r_hex = dec2hex(typecast(tx_real_q15(i), 'uint16'), 4);
        i_hex = dec2hex(typecast(tx_imag_q15(i), 'uint16'), 4);
        
        fprintf(fid, '%s%s\n', r_hex, i_hex);
    end

    fclose(fid);
    fprintf('Generated %s with %d 32-bit hex entries successfully.\n\n', mem_file, num_samples);
end
