function simple_make_mem()
% =========================================================================
% Function Name : simple_make_mem
% Project       : Simple Rectangular Pulse Cross-Correlation on FPGA
% Description   : Generates simple_tx.mem for the Tx rectangular pulse:
%                   Tx = [0×250 zeros] + [1×1000 ones]  →  N_TX = 1250
%                 Encodes each sample as 32-bit Q1.15 complex word:
%                   bits[31:16] = Real (Q1.15 int16)
%                   bits[15:0]  = Imag (Q1.15 int16) = 0 (real signal)
%
% Expected Peak at Cross-Correlation Lag k = 250
%   Delay = 250 × 10 ns = 2.5 µs
%   Range = (3×10^8 × 2.5×10^-6) / 2 = 375 m = 0.375 km
% =========================================================================

    N_ZEROS = 250;
    N_ONES  = 1000;
    N_TX    = N_ZEROS + N_ONES;  % 1250 total samples

    fprintf('=====================================================\n');
    fprintf('  Simple Signal Q1.15 Memory Generator             \n');
    fprintf('=====================================================\n');
    fprintf('Tx = [%d zeros] + [%d ones]  (N_TX = %d)\n', N_ZEROS, N_ONES, N_TX);

    % Build signal: real part only, imaginary = 0
    tx_real = [zeros(N_ZEROS, 1); ones(N_ONES, 1)];  % real: 0 or 1
    % Q1.15 max representable = 32767/32768 ≈ 0.99997 → use 32767 for 1.0
    tx_real_q15 = int16(round(min(tx_real, 0.99996948) * 32768));
    tx_imag_q15 = int16(zeros(N_TX, 1));

    % Write hex memory file to absolute path (must match INIT_FILE in simple_top.v)
    script_dir = fileparts(mfilename('fullpath'));
    if isempty(script_dir), script_dir = pwd; end
    mem_file = fullfile(script_dir, '..', 'data', 'simple_tx.mem');
    fid = fopen(mem_file, 'w');
    if fid == -1
        error('Cannot open %s for writing.', mem_file);
    end
    for i = 1:N_TX
        real_u16 = typecast(tx_real_q15(i), 'uint16');
        imag_u16 = typecast(tx_imag_q15(i), 'uint16');
        fprintf(fid, '%04X%04X\n', real_u16, imag_u16);
    end
    fclose(fid);

    fprintf('Generated %s with %d 32-bit hex entries.\n', mem_file, N_TX);
    fprintf('  Entries [0000 : %04d]  = 00000000 (zeros)\n', N_ZEROS-1);
    fprintf('  Entries [%04d : %04d]  = 7FFF0000 (ones in Q1.15)\n', N_ZEROS, N_TX-1);
    fprintf('=====================================================\n\n');
end
