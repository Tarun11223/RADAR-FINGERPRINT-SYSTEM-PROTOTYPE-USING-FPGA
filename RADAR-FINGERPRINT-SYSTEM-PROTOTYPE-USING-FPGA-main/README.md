# FPGA Radar Matched Filter & Cross-Correlation Engine

[![Board](https://img.shields.io/badge/Target%20Board-Digilent%20Nexys%20A7--100T-red.svg)](https://digilent.com/reference/programmable-logic/nexys-a7/start)
[![FPGA](https://img.shields.io/badge/FPGA-Artix--7%20XC7A100T--1CSG324C-blue.svg)](https://www.xilinx.com/products/silicon-devices/fpga/artix-7.html)
[![Vivado](https://img.shields.io/badge/Vivado-2024.x%20%2F%202025.x-orange.svg)](https://www.xilinx.com/products/design-tools/vivado.html)
[![MATLAB](https://img.shields.io/badge/MATLAB-R2023b%2B-brightgreen.svg)](https://www.mathworks.com/products/matlab.html)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

An end-to-end, high-performance **Complex Matched Filter & Cross-Correlation Engine** implemented on the **Digilent Nexys A7-100T FPGA board** with real-time magnitude peak detection and **921,600 baud USB-UART** PC streaming interface.

This repository contains **two complete, self-contained implementations**:
1. **`lfm_chirp_radar/`** — **Main LFM Chirp Radar Project** ($19,071$ Rx samples, $2,119$ Tx samples, $16,953$ correlation lags).
2. **`simple_pulse_example/`** — **Pedagogical Rectangular Pulse Project** ($1,500$ Rx samples, $1,250$ Tx samples, $251$ correlation lags).

---

## 📁 Repository Structure

```
radar_cross_correlation/
├── README.md                              <- Root GitHub Documentation & Guide
├── Cross_Correlation_FPGA_Report.md       <- Full Mathematical & Engineering Report
│
├── lfm_chirp_radar/                       <- Main LFM Chirp Radar Project (19k Rx / 2.1k Tx)
│   ├── verilog/                           <- Synthesizable Verilog HDL Modules
│   │   ├── top.v                          <- Top-level integration & Q1.15 scaling
│   │   ├── correlator.v                   <- Sequential complex MAC correlator engine
│   │   ├── controller.v                   <- 9-State master FSM controller
│   │   ├── fifo.v                         <- Rx echo sample circular buffer RAM
│   │   ├── bram_tx.v                      <- Tx chirp dual-port Block RAM
│   │   ├── ram_corr.v                     <- Correlation results storage RAM
│   │   ├── peak_detector.v                <- Pipelined magnitude-squared peak finder
│   │   ├── uart_rx.v                      <- 921,600 baud UART receiver
│   │   └── uart_tx.v                      <- 921,600 baud UART transmitter
│   ├── matlab/                            <- MATLAB Verification & UI Flow
│   │   ├── make_mem.m                     <- Q1.15 BRAM hex generator (tx.mem)
│   │   ├── main.m                         <- Master orchestration script
│   │   ├── uart_send_receive.m            <- Serial stream I/O handler
│   │   ├── plot_results.m                 <- 4-Panel visual plotting suite
│   │   └── export_results_csv.m           <- Combined single CSV exporter
│   ├── data/                              <- Input Signal Files & Memory Maps
│   │   ├── LFM_Chirp_Tx_data.csv          <- Transmit Chirp IQ samples (2119 rows)
│   │   ├── LFM_Chirp_Rx_Data.csv          <- Received Echo IQ samples (19071 rows)
│   │   └── tx.mem                         <- Q1.15 hex initialization file
│   └── vivado/                            <- Vivado Synthesis & Constraints
│       ├── constraints.xdc                <- Board pin mapping & 100MHz timing
│       ├── build.tcl                      <- Batch synthesis & bitstream script
│       └── program.tcl                    <- Hardware Manager programmer script
│
└── simple_pulse_example/                  <- Pedagogical Rectangular Pulse (1.5k Rx / 1.25k Tx)
    ├── verilog/                           <- Parameterized Verilog Modules
    │   ├── simple_top.v                   <- Top-level for rectangular pulse
    │   ├── correlator.v                   <- Shared sequential MAC engine
    │   ├── controller.v                   <- Shared 9-State FSM
    │   ├── fifo.v                         <- Shared sample buffer
    │   ├── bram_tx.v                      <- Shared dual-port BRAM
    │   ├── ram_corr.v                     <- Shared output RAM
    │   ├── peak_detector.v                <- Shared pipelined peak detector
    │   ├── uart_rx.v                      <- Shared 921.6k UART Rx
    │   └── uart_tx.v                      <- Shared 921.6k UART Tx
    ├── matlab/                            <- MATLAB Verification Suite
    │   ├── simple_make_mem.m              <- Memory generator (simple_tx.mem)
    │   ├── simple_main.m                  <- Master orchestration script
    │   ├── simple_uart_send_receive.m     <- Serial stream I/O handler
    │   ├── simple_plot_results.m          <- Plotting script
    │   └── simple_export_csv.m            <- CSV exporter
    ├── data/                              <- Memory Files
    │   └── simple_tx.mem                  <- Rectangular pulse Q1.15 hex file
    └── vivado/                            <- Synthesis & Hardware Scripts
        ├── simple_constraints.xdc         <- Pin mapping & ILA probe widths
        ├── simple_build.tcl               <- Batch build script
        └── simple_program.tcl             <- Hardware programmer script
```

---

## 📊 Project Comparison Overview

| Metric / Feature | Main LFM Chirp Radar (`lfm_chirp_radar/`) | Pedagogical Pulse Example (`simple_pulse_example/`) |
|---|---|---|
| **Waveform Type** | Linear Frequency Modulation (LFM Chirp) | Rectangular Pulse ($0\text{s}$ then $1\text{s}$) |
| **Transmit Width ($N_{Tx}$)** | **$2,119$ samples** | **$1,250$ samples** ($250$ zeros + $1000$ ones) |
| **Receive Stream ($N_{Rx}$)** | **$19,071$ samples** | **$1,500$ samples** ($500$ zeros + $1000$ ones) |
| **Correlation Lags ($K_{total}$)** | **$16,953$ lags** | **$251$ lags** ($k = 0 \dots 250$) |
| **BRAM Tx Address Width** | 12 bits ($2^{12} = 4096$) | 11 bits ($2^{11} = 2048$) |
| **Correlation Address Width** | 15 bits ($2^{15} = 32768$) | 9 bits ($2^9 = 512$) |
| **Processing Gain ($PG$)** | $+33.26\text{ dB}$ ($10 \log_{10} 2119$) | $+30.97\text{ dB}$ ($10 \log_{10} 1250$) |
| **Expected Peak Lag ($k_{peak}$)** | **$k = 4,500$** | **$k = 250$** |
| **Target Propagation Delay** | **$45.00\ \mu\text{s}$** | **$2.50\ \mu\text{s}$** |
| **Calculated Target Distance** | **$6,750.0\text{ m } (6.75\text{ km})$** | **$375.0\text{ m } (0.375\text{ km})$** |
| **Execution Time @ 100MHz** | $\sim 35.5\text{ ms}$ | $\sim 3.1\text{ ms}$ |

---

## 🔬 Mathematical Foundations

### 1. Discrete Cross-Correlation Formula
The discrete cross-correlation sequence $R[k]$ computed by the hardware correlator for each lag $k$ is:

$$R[k] = \sum_{n=0}^{N_{Tx}-1} Rx[k + n] \cdot Tx^*[n], \quad k = 0, 1, \dots, N_{Rx} - N_{Tx}$$

For complex IQ signals $Rx = I_{rx} + j Q_{rx}$ and $Tx = I_{tx} + j Q_{tx}$:

$$\text{Re}(R[k]) = \sum_{n=0}^{N_{Tx}-1} \left( I_{rx}[k+n] I_{tx}[n] + Q_{rx}[k+n] Q_{tx}[n] \right)$$

$$\text{Im}(R[k]) = \sum_{n=0}^{N_{Tx}-1} \left( Q_{rx}[k+n] I_{tx}[n] - I_{rx}[k+n] Q_{tx}[n] \right)$$

### 2. Delay & Target Range Estimation
Target distance $R_{target}$ is extracted directly from the peak lag $\hat{k}_{peak} = \arg\max_{k} |R[k]|^2$:

$$\tau = \hat{k}_{peak} \cdot T_s = \frac{\hat{k}_{peak}}{F_s}$$

$$R_{target} = \frac{c \cdot \tau}{2} = \frac{c \cdot \hat{k}_{peak}}{2 \cdot F_s}$$

For system clock $F_s = 100\text{ MHz}$ ($T_s = 10\text{ ns}$):
- **Simple Rectangular Pulse**: $\hat{k}_{peak} = 250 \implies \tau = 2.50\ \mu\text{s} \implies R_{target} = 375.0\text{ m}$.
- **LFM Chirp Radar**: $\hat{k}_{peak} = 4500 \implies \tau = 45.00\ \mu\text{s} \implies R_{target} = 6750.0\text{ m } (6.75\text{ km})$.

---

## 🛠️ System Architecture

```
+-----------------------------------------------------------------------------------+
|                                TOP.V MODULE                                       |
|                                                                                   |
|  +--------------+    +--------------+    +--------------+    +-----------------+  |
|  |  UART_RX.V   |--->|    FIFO.V    |--->| CORRELATOR.V |--->|   RAM_CORR.V    |  |
|  | (921.6k Baud)|    | (Rx Buffer)  |    | (Complex MAC)|    | (Output Store)  |  |
|  +--------------+    +--------------+    +--------------+    +-----------------+  |
|                             ^                   ^                     |           |
|                             |                   |                     v           |
|                      +--------------+           |            +-----------------+  |
|                      |  BRAM_TX.V   |-----------+            | PEAK_DETECTOR.V |  |
|                      | (Tx Memory)  |                        | (Magnitude Search) |
|                      +--------------+                        +-----------------+  |
|                                                                       |           |
|                      +--------------+    +--------------+             |           |
|                      | CONTROLLER.V |<---|  UART_TX.V   |<------------+           |
|                      | (9-State FSM)|    | (921.6k Baud)|                         |
|                      +--------------+    +--------------+                         |
+-----------------------------------------------------------------------------------+
```

### Key Hardware Submodules:
- **`correlator.v`**: 3-stage pipelined DSP48 MAC engine (1 multiply-accumulate per clock cycle per lag).
- **`controller.v`**: Master 9-state finite state machine sequencing `IDLE` $\to$ `WAIT_RX` $\to$ `CORRELATE` $\to$ `PEAK_SEARCH` $\to$ `STREAM_TX` $\to$ `DONE`.
- **`peak_detector.v`**: Real-time pipelined magnitude-squared finder ($|R|^2 = I^2 + Q^2$) scanning all output lags in hardware.
- **`uart_rx.v` / `uart_tx.v`**: High-speed serial transceivers operating at 921,600 baud (108.5 clocks/bit @ 100MHz) with framing headers (`0xA55A`).

---
