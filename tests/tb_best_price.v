// ---------------------------------------------------------------------------
// tb_best_price.v  --  self-checking testbench for module `best`
//
// Written by Claude only to test Elliott's best module (src/best_price.v).
// Plain Verilog-2005: run in EDA Playground (Icarus Verilog) or with
//     iverilog -g2005 -o sim tests/tb_best_price.v src/best_price.v && vvp sim
//
// Checks (combinational module, no clock):
//   buy_index  = highest set bit of buy_levels   (valid when no_buy  == 0)
//   sell_index = lowest  set bit of sell_levels  (valid when no_sell == 0)
//   no_buy  = 1 exactly when buy_levels  is all zeros, otherwise 0
//   no_sell = 1 exactly when sell_levels is all zeros, otherwise 0
// An index is only checked while its no_* flag is 0.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_best_price;

    reg  [255:0] buy_levels  = 256'd0;
    reg  [255:0] sell_levels = 256'd0;
    wire [7:0]   buy_index;
    wire [7:0]   sell_index;
    wire         no_sell;
    wire         no_buy;

    best dut (
        .buy_levels  (buy_levels),
        .sell_levels (sell_levels),
        .buy_index   (buy_index),
        .sell_index  (sell_index),
        .no_sell     (no_sell),
        .no_buy      (no_buy)
    );

    integer errors = 0;
    integer checks = 0;
    reg [8*32-1:0] test_name = "start";

    reg        exp_no_buy, exp_no_sell;
    reg [7:0]  exp_buy_index, exp_sell_index;

    task model;
        input [255:0] buys;
        input [255:0] sells;
        integer i;
        begin
            exp_no_buy = 1'b1;  exp_buy_index  = 8'd0;
            exp_no_sell = 1'b1; exp_sell_index = 8'd0;
            for (i = 0; i < 256; i = i + 1)
                if (buys[i]) begin exp_no_buy = 1'b0; exp_buy_index = i; end
            for (i = 255; i >= 0; i = i - 1)
                if (sells[i]) begin exp_no_sell = 1'b0; exp_sell_index = i; end
        end
    endtask

    // set the inputs, wait for the logic to settle, then check the outputs
    task apply;
        input [255:0] buys;
        input [255:0] sells;
        begin
            buy_levels  = buys;
            sell_levels = sells;
            model(buys, sells);
            #2;
            checks = checks + 1;
            if (no_buy !== exp_no_buy || (!exp_no_buy && buy_index !== exp_buy_index)) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("FAIL [%0s] buy: got no_buy=%b index=%0d, expected no_buy=%b index=%0d (buy_levels=%h)",
                        test_name, no_buy, buy_index, exp_no_buy, exp_buy_index, buys);
            end
            if (no_sell !== exp_no_sell || (!exp_no_sell && sell_index !== exp_sell_index)) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("FAIL [%0s] sell: got no_sell=%b index=%0d, expected no_sell=%b index=%0d (sell_levels=%h)",
                        test_name, no_sell, sell_index, exp_no_sell, exp_sell_index, sells);
            end
            #3;
        end
    endtask

    function [255:0] bit_at;
        input integer i;
        begin
            bit_at = 256'd0;
            bit_at[i] = 1'b1;
        end
    endfunction

    function [255:0] rand_map;      // each bit set with probability pct/100
        input integer pct;
        integer i, r;
        reg [255:0] m;
        begin
            m = 256'd0;
            for (i = 0; i < 256; i = i + 1) begin
                r = $random;
                if (r < 0) r = -r;
                if ((r % 100) < pct) m[i] = 1'b1;
            end
            rand_map = m;
        end
    endfunction

    integer i, j, pct, r;
    reg [255:0] b, a;

    initial begin
        #5;

        test_name = "empty";
        apply(256'd0, 256'd0);

        test_name = "single buy";
        apply(bit_at(10), 256'd0);

        test_name = "single sell";
        apply(256'd0, bit_at(20));

        test_name = "one each side";
        apply(bit_at(100), bit_at(101));

        test_name = "edges";
        apply(bit_at(0),   bit_at(0));
        apply(bit_at(255), bit_at(255));
        apply(bit_at(0),   bit_at(255));
        apply(bit_at(255), bit_at(0));

        test_name = "several levels";
        b = 256'd0; a = 256'd0;
        b[3] = 1; b[77] = 1; b[200] = 1; b[5] = 1;
        a[140] = 1; a[133] = 1; a[250] = 1; a[135] = 1;
        apply(b, a);

        // the flags and indexes must follow the inputs both ways
        test_name = "best level empties";
        b[200] = 0; apply(b, a);
        b[77]  = 0; apply(b, a);
        a[133] = 0; apply(b, a);
        a[135] = 0; apply(b, a);
        b[5]   = 0; apply(b, a);
        b[3]   = 0; apply(b, a);            // buys now empty -> no_buy = 1
        a[140] = 0; a[250] = 0; apply(b, a); // sells now empty -> no_sell = 1

        // empty -> non-empty: no_* must go back to 0 (not stay stuck at 1)
        test_name = "empty then non-empty";
        apply(256'd0, 256'd0);
        apply(bit_at(50), bit_at(60));
        apply(256'd0, 256'd0);
        apply(bit_at(255), 256'd0);
        apply(256'd0, bit_at(0));
        apply(bit_at(1), bit_at(2));

        // non-empty -> empty -> same non-empty again
        test_name = "back to same";
        apply(bit_at(9), bit_at(9));
        apply(256'd0, 256'd0);
        apply(bit_at(9), bit_at(9));

        test_name = "all ones";
        apply({256{1'b1}}, {256{1'b1}});

        test_name = "walking one";
        for (i = 0; i < 256; i = i + 1)
            apply(bit_at(i), bit_at(255 - i));

        test_name = "walking zero";
        for (i = 0; i < 256; i = i + 1)
            apply(~bit_at(i), ~bit_at(255 - i));

        test_name = "same levels both sides";
        apply(bit_at(8) | bit_at(20), bit_at(8) | bit_at(20));

        // empty between every pair so a stuck flag or index would show
        test_name = "all single pairs";
        for (i = 0; i < 256; i = i + 1)
            for (j = 0; j < 256; j = j + 1)
                apply(bit_at(i), bit_at(j));

        test_name = "random";
        for (pct = 1; pct <= 90; pct = pct + 3)
            for (i = 0; i < 100; i = i + 1)
                apply(rand_map(pct), rand_map(pct));

        test_name = "random single edits";
        b = rand_map(3); a = rand_map(3);
        for (i = 0; i < 3000; i = i + 1) begin
            r = $random;
            if (r < 0) r = -r;
            if (r % 2) b[(r / 2) % 256] = ~b[(r / 2) % 256];
            else       a[(r / 2) % 256] = ~a[(r / 2) % 256];
            apply(b, a);
        end

        $display("----------------------------------------------");
        $display("best testbench: %0d input combinations checked", checks);
        if (errors == 0) $display("PASS: no errors");
        else             $display("FAIL: %0d errors", errors);
        $display("----------------------------------------------");
        $finish;
    end

    initial begin
        #50000000;
        $display("FAIL: testbench timed out");
        $finish;
    end

endmodule
