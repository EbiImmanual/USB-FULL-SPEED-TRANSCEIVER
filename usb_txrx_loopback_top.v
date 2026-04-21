
module usb_txrx_loopback_top (
    input  wire       clk,        // 48 MHz
    input  wire       rst,        // active?high

    // TX controls
    input  wire       tx_start,   // 1?cycle pulse
    input  wire [7:0] pid_in,
    input  wire [7:0] data_in,

    // RX status
    output wire       rx_active,
    output wire       rx_valid,
    output wire       rx_error,
    output wire [7:0] rx_data_out,
    output wire [7:0] rx_pid,
    output wire [15:0] rx_crc_captured,
    output wire  crc16_ok_latched,

    output wire eop_detected_out,
    output wire crc16_ok_raw_out,
    output wire [3:0] byte_count_out,
    output wire [15:0] crc_val
);

    // ---------------- TX instance ----------------
    wire dp_tx;
    wire dm_tx;

    usb_tx_top u_tx (
        .clk     (clk),
        .rst     (rst),
        .tx_start(tx_start),
        .pid_in  (pid_in),
        .data_in (data_in),
        .dp      (dp_tx),
        .dm      (dm_tx),
        .tx_busy (),
	.crc_val (crc_val)
 	
    );

    // ---------------- RX instance ----------------
    wire rst_n = ~rst;

    rx_top2 u_rx (
        .clk          (clk),
        .rst_n        (rst_n),
        .dp_raw       (dp_tx),          // loopback connection
        .dn_raw       (dm_tx),          // loopback connection
        .rx_active    (rx_active),
        .rx_valid     (rx_valid),
        .rx_error     (rx_error),
        .data_out     (rx_data_out),
        .pid          (rx_pid),
        .crc_captured (rx_crc_captured),
	.crc16_ok_latched     (crc16_ok_latched),
	.eop_detected_out    (eop_detected_out),
	.crc16_ok_raw_out    (crc16_ok_raw_out),
	.byte_count_out     (byte_count_out)
    );

endmodule


