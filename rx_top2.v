
module rx_synchronizer (
    input  wire clk, input  wire rst_n,
    input  wire dp_raw, input  wire dn_raw,
    output reg  dp_sync, output reg  dn_sync
);
    reg dp_ff, dn_ff;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin dp_ff<=0; dn_ff<=0; dp_sync<=0; dn_sync<=0; end
        else begin dp_ff<=dp_raw; dp_sync<=dp_ff; dn_ff<=dn_raw; dn_sync<=dn_ff; end
    end
endmodule

module rx_sample_strobe #(parameter integer CLK_PER_BIT = 4) (
    input  wire clk, input  wire rst_n, output reg  sample_strobe
);
    reg [7:0] cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin cnt<=0; sample_strobe<=0; end
        else if (cnt == CLK_PER_BIT - 1) begin cnt<=0; sample_strobe<=1; end
        else begin cnt<=cnt+1; sample_strobe<=0; end
    end
endmodule

module rx_diff_decoder (
    input  wire clk, input  wire rst_n,
    input  wire dp_sync, input  wire dn_sync, input  wire sample_strobe,
    output reg  [1:0] state, output reg  bit_level, output reg  valid
);
    localparam SE0 = 2'b00; localparam J = 2'b01; localparam K = 2'b10;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin state<=SE0; bit_level<=0; valid<=0; end
        else begin
            valid <= 0;
            if (sample_strobe) begin
                if (!dp_sync && !dn_sync) state <= SE0;
                else if (dp_sync && !dn_sync) state <= J;
                else if (!dp_sync && dn_sync) state <= K;
                
                bit_level <= (dp_sync && !dn_sync); 
                valid <= 1;
            end
        end
    end
endmodule

module rx_nrzi_decoder (
    input  wire clk, input  wire rst_n,
    input  wire bit_level, input  wire valid,
    output reg  nrzi_bit, output reg  nrzi_valid
);
    reg prev_level;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin prev_level<=0; nrzi_bit<=0; nrzi_valid<=0; end
        else begin
            nrzi_valid <= 0;
            if (valid) begin
                nrzi_bit <= (bit_level == prev_level); 
                prev_level <= bit_level;
                nrzi_valid <= 1;
            end
        end
    end
endmodule

module rx_bit_unstuff (
    input  wire clk, input  wire rst_n,
    input  wire nrzi_bit, input  wire nrzi_valid,
    output reg  data_bit, output reg  data_valid, output reg bit_stuff_error
);
    reg [2:0] one_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin one_cnt<=0; data_bit<=0; data_valid<=0; bit_stuff_error<=0; end
        else begin
            data_valid <= 0;
            bit_stuff_error <= 0;
            if (nrzi_valid) begin
                if (nrzi_bit) begin
                    data_bit <= 1; data_valid <= 1; one_cnt <= one_cnt + 1;
                    if (one_cnt == 6) bit_stuff_error <= 1; 
                end else begin
                    if (one_cnt == 6) one_cnt <= 0;
                    else begin data_bit <= 0; data_valid <= 1; one_cnt <= 0; end
                end
            end
        end
    end
endmodule

module rx_sync_detect (
    input  wire clk, input  wire rst_n,
    input  wire data_bit, input  wire data_valid,
    output reg  sync_detected
);
    reg [7:0] shift;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin shift<=0; sync_detected<=0; end
        else begin
            sync_detected <= 0;
            if (data_valid) begin
                shift <= {data_bit, shift[7:1]};
                if ({data_bit, shift[7:1]} == 8'b10000000) 
                    sync_detected <= 1;
            end
        end
    end
endmodule

module rx_sipo (
    input  wire clk, input  wire rst_n,
    input  wire data_bit, input  wire data_valid, input  wire sync_detected,
    output reg  [7:0] byte_out, output reg  byte_valid
);
    reg [2:0] bit_cnt;
    reg [7:0] shift;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin bit_cnt<=0; shift<=0; byte_valid<=0; end
        else begin
            byte_valid <= 0;
            if (sync_detected) bit_cnt <= 0;
            if (data_valid) begin
                shift <= {data_bit, shift[7:1]};
                bit_cnt <= bit_cnt + 1'b1;
                if (bit_cnt == 3'd7) begin
                    byte_out <= {data_bit, shift[7:1]};
                    byte_valid <= 1;
                    bit_cnt <= 0;
                end
            end
        end
    end
endmodule

module rx_eop_detect (
    input  wire clk, input  wire rst_n,
    input  wire [1:0] state, input  wire valid,
    output reg  eop_detected
);
    reg se0_seen;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin se0_seen<=0; eop_detected<=0; end
        else begin
            eop_detected <= 0;
            if (valid) begin
                if (state == 0) begin 
                    if (se0_seen) begin eop_detected <= 1; se0_seen <= 0; end
                    else se0_seen <= 1;
                end else se0_seen <= 0;
            end
        end
    end
endmodule

module rx_fsm_ref (
    input  wire clk, input  wire rst_n,
    input  wire sync_detected, 
    input  wire eop_detected,
    input  wire byte_valid,
    input  wire bit_stuff_error,
    
    output reg rx_active,
    output reg rx_valid,
    output reg rx_error
);
    localparam RX_WAIT      = 3'd0;
    localparam STRIP_SYNC   = 3'd1;
    localparam RX_DATA      = 3'd2;
    localparam RX_DATA_WAIT = 3'd3; 
    localparam STRIP_EOP    = 3'd4;
    localparam ABORT        = 3'd5;

    reg [2:0] current_state, next_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= RX_WAIT;
        else current_state <= next_state;
    end

    always @(*) begin
        next_state = current_state;
        rx_active = 0;
        rx_valid = 0;
        rx_error = 0;

        case (current_state)
            RX_WAIT: begin
                if (sync_detected) next_state = STRIP_SYNC;
            end

            STRIP_SYNC: begin
                rx_active = 1;
                next_state = RX_DATA_WAIT; 
            end

            RX_DATA_WAIT: begin
                rx_active = 1;
                if (eop_detected) next_state = STRIP_EOP;
                else if (bit_stuff_error) next_state = ABORT;
                else if (byte_valid) next_state = RX_DATA;
            end

            RX_DATA: begin
                rx_active = 1;
                rx_valid = 1; 
                next_state = RX_DATA_WAIT; 
            end

            STRIP_EOP: begin
                rx_active = 0; 
                next_state = RX_WAIT;
            end

            ABORT: begin
                rx_error = 1;
                rx_active = 0;
                next_state = RX_WAIT;
            end
            
            default: next_state = RX_WAIT;
        endcase
    end
endmodule

module usb_crc16_checker (
    input  wire [15:0] crc_received,
    output wire        crc_ok
);
    // USB CRC16 residue is always 0xB001 when correct
    assign crc_ok = (crc_received == 16'hB001);
endmodule



module rx_top2 (
    input  wire clk,
    input  wire rst_n,
    input  wire dp_raw,
    input  wire dn_raw,
    
    output wire rx_active,     
    output wire rx_valid,      
    output wire rx_error,      
    output wire [7:0] data_out,
    output reg  [7:0] pid,
    output reg  [15:0] crc_captured,
    output reg  crc16_ok_latched,
    
    // DEBUG outputs for waveform
    output wire eop_detected_out,
    output wire crc16_ok_raw_out,
    output reg  [3:0] byte_count_out
);
  
    //================================================================
    // Internal Wires
    //================================================================
    wire dp_sync, dn_sync, sample_strobe;
    wire [1:0] state;
    wire bit_level, valid, nrzi_bit, nrzi_valid;
    wire data_bit, data_valid, bit_stuff_error;
    wire sync_detected, byte_valid, eop_detected;
    wire [7:0] byte_out;
    
    //================================================================
    // Registers for CRC capture
    //================================================================
    reg [15:0] crc_temp;           // Temporary CRC storage during packet
    reg [3:0] byte_count;          // Count received bytes
    
    //================================================================
    // Sub-modules Instantiation
    //================================================================
    rx_synchronizer  u1 (clk, rst_n, dp_raw, dn_raw, dp_sync, dn_sync);
    rx_sample_strobe u2 (clk, rst_n, sample_strobe);
    rx_diff_decoder  u3 (clk, rst_n, dp_sync, dn_sync, sample_strobe, state, bit_level, valid);
    rx_nrzi_decoder  u4 (clk, rst_n, bit_level, valid, nrzi_bit, nrzi_valid);
    rx_bit_unstuff   u5 (clk, rst_n, nrzi_bit, nrzi_valid, data_bit, data_valid, bit_stuff_error);
    rx_sync_detect   u6 (clk, rst_n, data_bit, data_valid, sync_detected);
    rx_sipo          u7 (clk, rst_n, data_bit, data_valid, sync_detected, byte_out, byte_valid);
    rx_eop_detect    u8 (clk, rst_n, state, valid, eop_detected);

    rx_fsm_ref u9 (
        .clk(clk), 
        .rst_n(rst_n),
        .sync_detected(sync_detected),
        .eop_detected(eop_detected),
        .byte_valid(byte_valid),
        .bit_stuff_error(bit_stuff_error),
        .rx_active(rx_active),
        .rx_valid(rx_valid),
        .rx_error(rx_error)
    );

    //================================================================
    // CRC16 Checker Module
    //================================================================
    wire crc16_ok_raw;
    usb_crc16_checker u_crc_check (
        .crc_received(crc_temp),
        .crc_ok(crc16_ok_raw)
    );

    //================================================================
    // DEBUG Outputs
    //================================================================
    assign eop_detected_out = eop_detected;
    assign crc16_ok_raw_out = crc16_ok_raw;

    //================================================================
    // CRC16 Temporary Storage (during packet reception)
    //================================================================
    // Store last 2 bytes in crc_temp as they arrive
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_temp <= 16'h0000;
        end else begin
            if (sync_detected) begin
                // Reset on new SYNC
                crc_temp <= 16'h0000;
            end else if (byte_valid) begin
                // Shift in new byte: low byte → high byte, new byte → low byte
                crc_temp <= {crc_temp[7:0], byte_out};
            end
        end
    end

    //================================================================
    // Latch CRC16 Result when EOP is detected
    //================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc16_ok_latched <= 1'b0;
            crc_captured <= 16'h0000;
        end else begin
            if (eop_detected) begin
                // Latch the CRC result when packet ends
                crc16_ok_latched <= crc16_ok_raw;
                crc_captured <= crc_temp;
                
                // DEBUG: Display result
                if (crc16_ok_raw == 1'b1)
                    $display("[%0t] CRC16 VALID: 0x%04X", $time, crc_temp);
                else
                    $display("[%0t] CRC16 INVALID: 0x%04X", $time, crc_temp);
            end
        end
    end

    //================================================================
    // Byte Counter and PID capture
    //================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pid <= 8'h00;
            byte_count <= 4'h0;
            byte_count_out <= 4'h0;
        end else begin
            if (sync_detected) begin
                // Reset byte counter on SYNC
                byte_count <= 4'h0;
            end else if (byte_valid) begin
                // Capture PID (first byte after SYNC)
                if (byte_count == 4'h0) begin
                    pid <= byte_out;
                end
                
                // Increment byte counter
                byte_count <= byte_count + 1'b1;
            end
            
            // Export for debug
            byte_count_out <= byte_count;
        end
    end

    //================================================================
    // Main Data Output
    //================================================================
    assign data_out = byte_out;

endmodule

