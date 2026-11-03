`timescale 1ns/1ps
// Self-checking testbench for parse.v (the 18-byte message parser).
// Plain Verilog, so it runs on EDA Playground or any simulator.
//
// Message layout (big-endian):
//   byte 0      type ('A','E','X','D','U')
//   bytes 1-4   order ID
//   byte 5      side ('B'/'S', add only)
//   bytes 6-9   shares
//   bytes 10-13 price (4 implied decimals: 501000 = $50.1000)
//   bytes 14-17 new order ID (replace only)

module tb_parse;

    // ---------------------------------------------------------------- DUT
    reg         clk = 0;
    reg         valid = 0;
    reg  [7:0]  data = 0;
    wire        msg_valid;
    wire [31:0] price, ID, qty, new_ID;
    wire [7:0]  msg_type, side;

    // Connected by position (same order as the ports in parse.v), so this works
    // whether the port is called `type` or `msg_type`.
    parse dut (clk, valid, data, msg_valid, price, msg_type, ID, side, qty, new_ID);

    always #5 clk = ~clk;   // 10 ns clock

    // ---------------------------------------------------------------- scoreboard
    // Every message sent is stored here; every message the parser outputs is
    // compared against the next one in line.
    reg [7:0]  exp_type  [0:1023];
    reg [31:0] exp_id    [0:1023];
    reg [7:0]  exp_side  [0:1023];
    reg [31:0] exp_qty   [0:1023];
    reg [31:0] exp_price [0:1023];
    reg [31:0] exp_newid [0:1023];
    integer sent = 0;        // messages sent
    integer checked = 0;     // messages the parser output
    integer errors = 0;
    integer valid_cycles = 0;
    reg     prev_msg_valid = 0;

    // Look at the outputs just after every rising edge.
    always @(posedge clk) begin
        #1;
        if (msg_valid) begin
            valid_cycles = valid_cycles + 1;
            if (prev_msg_valid) begin
                $display("ERROR: msg_valid was high for two cycles in a row (t=%0t)", $time);
                errors = errors + 1;
            end
            if (checked >= sent) begin
                $display("ERROR: msg_valid fired but no message was sent (t=%0t)", $time);
                errors = errors + 1;
            end else begin
                if (msg_type !== exp_type[checked] || ID     !== exp_id[checked]    ||
                    side     !== exp_side[checked] || qty    !== exp_qty[checked]   ||
                    price    !== exp_price[checked]|| new_ID !== exp_newid[checked]) begin
                    $display("ERROR: message %0d mismatch (t=%0t)", checked, $time);
                    $display("   got      type=%c id=%h side=%h qty=%0d price=%0d new_id=%h",
                             msg_type, ID, side, qty, price, new_ID);
                    $display("   expected type=%c id=%h side=%h qty=%0d price=%0d new_id=%h",
                             exp_type[checked], exp_id[checked], exp_side[checked],
                             exp_qty[checked], exp_price[checked], exp_newid[checked]);
                    errors = errors + 1;
                end
            end
            checked = checked + 1;
        end
        prev_msg_valid = msg_valid;
    end

    // ---------------------------------------------------------------- driver
    integer gap_percent = 0;   // chance (0-100) of an idle cycle before each byte

    task send_byte(input [7:0] b);
        begin
            while (($random & 32'h7fffffff) % 100 < gap_percent) begin
                @(negedge clk) valid = 0;     // idle cycle
            end
            @(negedge clk) begin
                valid = 1;
                data  = b;
            end
        end
    endtask

    task send_msg(input [7:0] t, input [31:0] id, input [7:0] s,
                  input [31:0] q, input [31:0] p, input [31:0] nid);
        integer i;
        reg [143:0] bytes;
        begin
            exp_type[sent] = t;  exp_id[sent] = id;  exp_side[sent] = s;
            exp_qty[sent]  = q;  exp_price[sent] = p; exp_newid[sent] = nid;
            sent = sent + 1;

            bytes = {t, id, s, q, p, nid};
            for (i = 17; i >= 0; i = i - 1)
                send_byte(bytes[i*8 +: 8]);

            // msg_valid should rise on the same edge that captures the last byte
            @(posedge clk) #1;
            if (msg_valid !== 1'b1) begin
                $display("ERROR: msg_valid was not high right after the last byte (t=%0t)", $time);
                errors = errors + 1;
            end
        end
    endtask

    task idle(input integer cycles);
        begin
            @(negedge clk) valid = 0;
            repeat (cycles) @(negedge clk);
        end
    endtask

    // Shortcuts for each message type (unused fields are 0)
    task add_order (input [31:0] id, input [7:0] s, input [31:0] q, input [31:0] p);
        send_msg("A", id, s, q, p, 0);
    endtask
    task execute   (input [31:0] id, input [31:0] q);  send_msg("E", id, 0, q, 0, 0); endtask
    task cancel    (input [31:0] id, input [31:0] q);  send_msg("X", id, 0, q, 0, 0); endtask
    task delete    (input [31:0] id);                  send_msg("D", id, 0, 0, 0, 0); endtask
    task replace   (input [31:0] id, input [31:0] nid, input [31:0] q, input [31:0] p);
        send_msg("U", id, 0, q, p, nid);
    endtask

    task random_msg;
        reg [2:0] k;
        begin
            k = ($random & 32'h7fffffff) % 5;
            case (k)
                0: add_order($random, (($random & 1) ? "B" : "S"), ($random & 32'h3fff) + 1, $random);
                1: execute($random, ($random & 32'h3fff) + 1);
                2: cancel($random, ($random & 32'h3fff) + 1);
                3: delete($random);
                default: replace($random, $random, ($random & 32'h3fff) + 1, $random);
            endcase
        end
    endtask

    task check_point(input [8*40-1:0] name, input integer errors_before);
        begin
            idle(5);
            if (errors == errors_before && checked == sent)
                $display("PASS  %0s", name);
            else begin
                if (checked != sent) begin
                    $display("ERROR: sent %0d messages but parser output %0d", sent, checked);
                    errors = errors + 1;
                end
                $display("FAIL  %0s", name);
            end
        end
    endtask

    // ---------------------------------------------------------------- tests
    integer n, e0;
    initial begin
        $dumpfile("dump.vcd");      // waveforms (EDA Playground: tick "Open EPWave after run")
        $dumpvars(0, tb_parse);

        idle(3);

        // 1. one add order: buy 100 @ $50.10, order #42
        e0 = errors;
        add_order(42, "B", 100, 501000);
        check_point("single add order", e0);

        // 2. every message type, back to back
        e0 = errors;
        add_order(42, "B", 100, 501000);
        execute(42, 30);
        cancel(42, 20);
        replace(42, 43, 75, 501200);
        delete(43);
        check_point("every message type", e0);

        // 3. a different byte in every position (catches byte-order mistakes)
        e0 = errors;
        add_order(32'h01020304, "S", 32'h05060708, 32'h090A0B0C);
        replace(32'h11223344, 32'h55667788, 32'h99AABBCC, 32'hDDEEFF01);
        check_point("big-endian byte order", e0);

        // 4. all-ones and all-zero fields
        e0 = errors;
        add_order(32'hFFFFFFFF, "B", 32'hFFFFFFFF, 32'hFFFFFFFF);
        replace(0, 0, 0, 0);
        replace(32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFF);
        check_point("max and zero values", e0);

        // 5. 200 random messages, one byte every clock
        e0 = errors;
        gap_percent = 0;
        for (n = 0; n < 200; n = n + 1) random_msg;
        check_point("200 random, back to back", e0);

        // 6. 200 random messages with random idle cycles
        e0 = errors;
        gap_percent = 30;
        for (n = 0; n < 200; n = n + 1) random_msg;
        gap_percent = 0;
        check_point("200 random, with gaps", e0);

        // 7. nothing happens while valid is low
        e0 = errors;
        @(negedge clk) begin valid = 0; data = "A"; end
        repeat (100) @(negedge clk);
        check_point("idle: no output while valid is low", e0);

        // msg_valid must have been high for exactly one cycle per message
        if (valid_cycles != sent) begin
            $display("ERROR: msg_valid was high for %0d cycles for %0d messages", valid_cycles, sent);
            errors = errors + 1;
        end

        $display("--------------------------------------------");
        if (errors == 0)
            $display("ALL TESTS PASSED  (%0d messages checked)", checked);
        else
            $display("FAILED: %0d error(s)", errors);
        $display("--------------------------------------------");
        $finish;
    end

endmodule
