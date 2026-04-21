
`timescale 1ns/1ps

module tb_usb_txrx_loopback_top;

    // Clock & reset
    reg clk;
    reg rst;

    // TX control
    reg        tx_start;
    reg [7:0]  pid_in;
    reg [7:0]  data_in;

    // RX status
    wire       rx_active;
    wire       rx_valid;
    wire       rx_error;
    wire [7:0] rx_data_out;
    wire [7:0] rx_pid;
    wire [15:0] rx_crc_captured;
    wire crc16_ok;

     wire [15:0] crc_val;
	wire eop_detected_out;
     wire crc16_ok_raw_out;
    wire[3:0] byte_count_out;
    // 48?MHz clock (20 ns)
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    // DUT
    usb_txrx_loopback_top dut (
        .clk            (clk),
        .rst            (rst),
        .tx_start       (tx_start),
        .pid_in         (pid_in),
        .data_in        (data_in),
        .rx_active      (rx_active),
        .rx_valid       (rx_valid),
        .rx_error       (rx_error),
        .rx_data_out    (rx_data_out),
        .rx_pid         (rx_pid),
        .rx_crc_captured(rx_crc_captured),
	.crc16_ok_latched       (crc16_ok),
	.crc_val   (crc_val),
	.eop_detected_out (eop_detected_out),
  . crc16_ok_raw_out(crc16_ok_raw_out),
    .byte_count_out  (byte_count_out)
    );

    // Stimulus
    initial begin
        rst      = 1'b1;
        tx_start = 1'b0;
        pid_in   = 8'h00;
        data_in  = 8'h00;

        // Hold reset
        repeat(10) @(posedge clk);
        rst = 1'b0;

        // Wait some cycles
        repeat(10) @(posedge clk);

        // Configure PID and DATA
        //pid_in  = 8'hA5;
        data_in = 8'h44;

        // Start packet (one?cycle pulse)
        @(posedge clk);
        tx_start <= 1'b1;
        @(posedge clk);
        tx_start <= 1'b0;

        // Run long enough for full packet + RX
        // 40 bits * 4 clocks/bit ? 160 clocks, add margin
        repeat(400) @(posedge clk);

        $finish;
    end

    // Monitor RX results
    initial begin
        $dumpfile("usb_txrx_loopback_top_tb.vcd");
        $dumpvars(0, tb_usb_txrx_loopback_top);

        $display("time\tactive\tvalid\terror\tdata_out\tpid");
        forever begin
            @(posedge clk);
            if (rx_valid)
                $display("%0t\t%b\t%b\t%b\t%02h\t\t%02h",
                         $time, rx_active, rx_valid, rx_error,
                         rx_data_out, rx_pid);
        end
    end

endmodule
