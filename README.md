# USB Full-Speed Transceiver — Loopback (Verilog)

A complete **USB Full-Speed (12 Mbps)** transmit + receive pipeline implemented in synthesizable RTL Verilog, with a loopback testbench for end-to-end verification.

---

## 📁 File Structure

```
├── usb_tx_top.v                  # Full-speed USB transmitter
├── rx_top2.v                     # Full-speed USB receiver
├── usb_txrx_loopback_top.v       # Loopback top — wires TX into RX
└── tb_usb_txrx_loopback_top.v    # Self-checking loopback testbench
```

---

## 🔌 Overview

This project implements a complete USB Full-Speed transceiver from scratch, including:

- **12 Mbps bit timing** via a 48 MHz system clock divided by 4
- **Bit stuffing / unstuffing** (insert/remove `0` after 6 consecutive `1`s)
- **NRZI encoding and decoding**
- **Differential DP/DM line driving and sampling**
- **USB CRC-16** generation (polynomial 0x8005, reflected) and residue checking (0xB001)
- **EOP (End of Packet)** generation (SE0 × 2 bit times + J) and detection
- **Full byte-level FSM** on the TX side and **bit/byte-level pipeline** on the RX side

The loopback top connects the TX `dp`/`dm` outputs directly to the RX `dp_raw`/`dn_raw` inputs, allowing the full transmit-then-receive chain to be tested in simulation without any external hardware.

---

## 🧩 Module Breakdown

### Transmitter — `usb_tx_top.v`

| Sub-module | Description |
|---|---|
| `usb_bit_timer` | Divides 48 MHz clock by 4 to produce a 12 Mbps bit-enable strobe |
| `usb_p2s` | Parallel-to-serial shift register, LSB first |
| `usb_bit_stuff` | Inserts a stuffed `0` bit after every 6 consecutive `1` bits |
| `usb_nrzi` | NRZI encoder — toggles output on each `0` bit |
| `usb_dpdm` | Differential DP/DM driver; asserts SE0 (both low) during EOP |
| `usb_crc16` | CRC-16 over PID + DATA bytes (before stuffing, LSB first) |

**TX packet byte order (USB spec):**
```
SYNC (0x80) → PID → DATA → CRC16[7:0] → CRC16[15:8] → EOP
```

**TX FSM states:**
```
IDLE → SYNC → PID → DATA → CRC0 → CRC1 → EOP → IDLE
```

---

### Receiver — `rx_top2.v`

| Sub-module | Description |
|---|---|
| `rx_synchronizer` | 2-FF synchronizer for DP/DM inputs into the clock domain |
| `rx_sample_strobe` | Generates a sample pulse every 4 clock cycles (12 Mbps) |
| `rx_diff_decoder` | Decodes DP/DM into J / K / SE0 line states |
| `rx_nrzi_decoder` | Reverses NRZI encoding to recover the raw bit stream |
| `rx_bit_unstuff` | Removes stuffed `0` bits; flags error on 7 consecutive `1`s |
| `rx_sync_detect` | Detects USB SYNC pattern (0x80 = `KJKJKJKK`) |
| `rx_sipo` | Serial-in parallel-out — assembles 8 bits into a byte |
| `rx_eop_detect` | Detects two consecutive SE0 samples = End of Packet |
| `rx_fsm_ref` | RX control FSM: `WAIT → STRIP_SYNC → RX_DATA → STRIP_EOP / ABORT` |
| `usb_crc16_checker` | Validates CRC residue == `0xB001` for a correct packet |

**Captured outputs per packet:**
- `rx_pid` — first byte after SYNC
- `data_out` — most recent received byte
- `crc_captured` — last 2 bytes (CRC field)
- `crc16_ok_latched` — `1` if CRC residue is valid
- `byte_count_out` — number of bytes received
- `eop_detected_out` — pulse on EOP detection

---

### Loopback Top — `usb_txrx_loopback_top.v`

Instantiates one `usb_tx_top` and one `rx_top2` and connects them:

```
dp_tx ──────────────────► dp_raw
dm_tx ──────────────────► dn_raw
rst   ── invert (~) ────► rst_n
```

---

## 🧪 Testbench — `tb_usb_txrx_loopback_top.v`

- **Clock:** 48 MHz (20 ns period)
- **Stimulus:** Sends one USB packet with `data_in = 0x44`
- **Duration:** 400 clock cycles (enough for full TX + RX pipeline)
- **Outputs:** VCD waveform dump + console display of every valid received byte

**Run with any Verilog simulator (e.g. Icarus Verilog):**

```bash
iverilog -o usb_loopback tb_usb_txrx_loopback_top.v usb_txrx_loopback_top.v usb_tx_top.v rx_top2.v
vvp usb_loopback
gtkwave usb_txrx_loopback_top_tb.vcd
```

**Expected console output:**
```
time    active  valid   error   data_out    pid
...     1       1       0       44          00
```
And a `CRC16 VALID: 0x....` line printed from the RX module at EOP.

---

## ⚙️ Parameters & Assumptions

| Parameter | Value |
|---|---|
| System clock | 48 MHz |
| USB speed | Full-Speed (12 Mbps) |
| Clocks per bit | 4 |
| CRC polynomial | 0x8005 (reflected → 0xA001) |
| CRC init value | 0xFFFF |
| CRC valid residue | 0xB001 |
| SYNC byte | 0x80 |
| EOP | SE0 × 2 bit times + J |
| Reset polarity | TX: active-high / RX: active-low |

---

## 📐 Architecture Diagram

```
                    ┌─────────────────────────────────┐
  tx_start ────────►│                                 │
  pid_in   ────────►│        usb_tx_top               │──── dp_tx ──┐
  data_in  ────────►│  (SYNC→PID→DATA→CRC16→EOP)      │──── dm_tx ──┤
                    └─────────────────────────────────┘             │ (loopback)
                                                                     │
                    ┌─────────────────────────────────┐             │
  rx_active ◄───────│                                 │◄─── dp_raw ─┘
  rx_valid  ◄───────│        rx_top2                  │◄─── dn_raw ─┘
  rx_pid    ◄───────│  (sync→NRZI dec→unstuff→SIPO)   │
  rx_data   ◄───────│                                 │
  crc16_ok  ◄───────│                                 │
                    └─────────────────────────────────┘
```

---

## 📜 License

MIT License — free to use, modify, and distribute.
