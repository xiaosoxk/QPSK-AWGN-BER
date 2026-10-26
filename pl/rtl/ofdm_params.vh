// ofdm_params.vh — 全局参数（全工程唯一参数源, 与 golden/ofdm_golden.py 一致）
`ifndef OFDM_PARAMS_VH
`define OFDM_PARAMS_VH

`define N_FFT      64
`define CP_LEN     16
`define N_SYM      10                  // 每帧OFDM符号数
`define SYM_LEN    (`N_FFT + `CP_LEN)  // 80 采样/符号(含CP)
`define FRAME_LEN  (`SYM_LEN * `N_SYM) // 800 采样/帧
`define PILOT0     7                   // 导频bin(±7/±21)
`define PILOT1     21
`define PILOT2     43
`define PILOT3     57
`define N_DATA     48                  // 数据子载波数
`define N_PILOT    4
`define SAMPLE_W   16                  // I/Q 各16bit, Q1.14
`define SYM_W      32                  // {Q[15:0], I[15:0]}

// 数据bin判定: ±1..±26 中非导频 = 48个
// bin 0(DC), 27..37(保护), 导频4个 → 置零
function is_data_bin(input [6:0] k);
    begin
        is_data_bin = (k != 0) && (k != `PILOT0) && (k != `PILOT1)
                   && (k != `PILOT2) && (k != `PILOT3)
                   && ((k >= 1  && k <= 26) || (k >= 38 && k <= 63));
    end
endfunction
function is_pilot_bin(input [6:0] k);
    begin
        is_pilot_bin = (k == `PILOT0) || (k == `PILOT1)
                     || (k == `PILOT2) || (k == `PILOT3);
    end
endfunction

`endif
