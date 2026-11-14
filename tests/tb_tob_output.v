// ---------------------------------------------------------------------------
// tb_tob_output.v  --  self-checking testbench for module `tob`
//
// Written by Claude only to test Elliott's tob module (src/tob_output.v).
// Plain Verilog-2005: run in EDA Playground (Icarus Verilog) or with
//     iverilog -g2005 -o sim tests/tb_tob_output.v src/tob_output.v && vvp sim
//
// What tob must do
//   It watches the best bid and best ask coming out of `best` and pulses
//   best_change whenever either of them changes.
//
//   module tob(
//       input      clk,
//       input [7:0] buy_index,     // from best: best bid level
//       input [7:0] sell_index,    // from best: best ask level
//       input      no_sell,        // from best: 1 = no asks at all
//       input      no_buy,         // from best: 1 = no bids at all
//       output reg best_change     // 1 for exactly one clock per change
//   );
//
//   Rules
//   1. Every clock edge, compare the inputs with the last book reported.
//      The book "changed" if a side went empty or non-empty, or if a side that
//      is non-empty has a different index.
//   2. An index only counts while its no_* flag is 0. Like the real `best`,
//      this testbench never moves an index while its side is empty: when a
//      no_* flag is 1 the index wire simply keeps its last value.
//   3. If the book changed, best_change = 1 for exactly one clock right after
//      that clock edge, and 0 again on the next edge unless the book changed
//      again.
//   4. best_change is registered: it only changes on a clock edge (one clock
//      of latency).
//   5. At start-up the last reported book is "empty on both sides", so an
//      empty book at the start gives no pulse.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_tob_output;

    reg        clk = 1'b0;
    reg  [7:0] buy_index  = 8'd0;
    reg  [7:0] sell_index = 8'd0;
    reg        no_buy     = 1'b1;
    reg        no_sell    = 1'b1;
    wire       best_change;

    tob dut (
        .clk         (clk),
        .buy_index   (buy_index),
        .sell_index  (sell_index),
        .no_sell     (no_sell),
        .no_buy      (no_buy),
        .best_change (best_change)
    );

    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // Reference model: remembers the last reported book
    // ------------------------------------------------------------------
    reg        last_no_bid = 1'b1, last_no_ask = 1'b1;
    reg [7:0]  last_bid = 8'd0,    last_ask = 8'd0;

    reg        exp_valid;
    reg        changed;

    integer errors  = 0;
    integer cycles  = 0;
    integer updates = 0;
    integer started = 0;
    reg [8*32-1:0] test_name = "start";

    task check_outputs;
        input [8*12-1:0] when;
        begin
            if (best_change !== exp_valid) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("FAIL [%0s] %0s t=%0t best_change=%b, expected %b  (no_buy=%b buy_index=%0d no_sell=%b sell_index=%0d)",
                        test_name, when, $time, best_change, exp_valid,
                        no_buy, buy_index, no_sell, sell_index);
            end
        end
    endtask

    // At every rising edge the DUT samples the inputs (set on the falling
    // edge). The model decides whether the book changed and what the outputs
    // must show right after this edge.
    always @(posedge clk) begin
        changed = (no_buy  !== last_no_bid) || (!no_buy  && buy_index  !== last_bid) ||
                  (no_sell !== last_no_ask) || (!no_sell && sell_index !== last_ask);
        exp_valid = changed;
        if (changed) begin
            last_no_bid = no_buy;  last_bid = buy_index;
            last_no_ask = no_sell; last_ask = sell_index;
            updates = updates + 1;
        end
        started = 1;
        cycles  = cycles + 1;
        #1;
        check_outputs("after edge");
    end

    // Registered outputs must not move when the inputs change (falling edge).
    always @(negedge clk) begin
        #2;
        if (started) check_outputs("held");
    end

    // ------------------------------------------------------------------
    // Stimulus helpers: inputs change on the falling edge, like real logic
    // ------------------------------------------------------------------
    // Like the real `best`: while a side is empty its index wire holds the
    // last value it had, whatever number the test asks for.
    task set;
        input       nb;
        input [7:0] bi;
        input       ns;
        input [7:0] si;
        begin
            @(negedge clk);
            no_buy = nb;  if (!nb) buy_index  = bi;
            no_sell = ns; if (!ns) sell_index = si;
        end
    endtask

    task idle;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) @(negedge clk);
        end
    endtask

    integer i, r, mode;
    reg        nb, ns;
    reg [7:0]  bi, si;

    // ------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------
    initial begin
        idle(4);

        test_name = "empty book sends nothing";
        set(1, 8'd0, 1, 8'd0);
        idle(5);

        test_name = "stale index while empty";
        set(1, 8'd77, 1, 8'd200);       // junk on the index wires, flags say empty
        idle(2);
        set(1, 8'd13, 1, 8'd250);
        idle(3);

        test_name = "bid appears";
        set(0, 8'd110, 1, 8'd13);
        idle(4);                        // held: only ONE update

        test_name = "ask appears";
        set(0, 8'd110, 0, 8'd122);
        idle(4);

        test_name = "bid improves";
        set(0, 8'd114, 0, 8'd122);
        idle(3);

        test_name = "bid worsens";
        set(0, 8'd110, 0, 8'd122);
        idle(3);

        test_name = "ask improves";
        set(0, 8'd110, 0, 8'd119);
        idle(3);

        test_name = "ask worsens";
        set(0, 8'd110, 0, 8'd126);
        idle(3);

        test_name = "no change";
        set(0, 8'd110, 0, 8'd126);
        idle(3);

        test_name = "both change at once";
        set(0, 8'd115, 0, 8'd120);
        idle(3);

        test_name = "changes on consecutive clocks";
        set(0, 8'd116, 0, 8'd120);
        set(0, 8'd117, 0, 8'd120);
        set(0, 8'd117, 0, 8'd119);
        set(0, 8'd118, 0, 8'd118);
        idle(3);

        test_name = "change and change back";
        set(0, 8'd50, 0, 8'd118);
        set(0, 8'd118, 0, 8'd118);
        set(0, 8'd50, 0, 8'd118);
        idle(3);

        test_name = "bid side empties";
        set(1, 8'd50, 0, 8'd118);       // index stays at old value, flag says empty
        idle(3);

        test_name = "index moves while bid empty";
        set(1, 8'd51, 0, 8'd118);
        set(1, 8'd99, 0, 8'd118);
        set(1, 8'd0,  0, 8'd118);
        idle(3);

        test_name = "bid returns, same index as before";
        set(0, 8'd50, 0, 8'd118);
        idle(3);

        test_name = "ask side empties and returns";
        set(0, 8'd50, 1, 8'd118);
        idle(2);
        set(0, 8'd50, 1, 8'd7);          // stale index moves: no update
        idle(2);
        set(0, 8'd50, 0, 8'd118);
        idle(3);

        test_name = "both sides empty";
        set(1, 8'd50, 1, 8'd118);
        idle(3);
        set(1, 8'd0, 1, 8'd0);           // still empty: no update
        idle(3);

        test_name = "index 0 and 255 are real prices";
        set(0, 8'd0,   1, 8'd0);         // bid at level 0 is not "empty"
        idle(2);
        set(0, 8'd0,   0, 8'd255);
        idle(2);
        set(0, 8'd255, 0, 8'd0);
        idle(2);
        set(0, 8'd255, 0, 8'd255);
        idle(2);

        test_name = "every bid index";
        for (i = 0; i < 256; i = i + 1) begin
            set(0, i[7:0], 0, 8'd200);
            idle(1);
        end

        test_name = "every ask index, back to back";
        for (i = 0; i < 256; i = i + 1)
            set(0, 8'd10, 0, i[7:0]);
        idle(3);

        test_name = "random held";
        for (i = 0; i < 3000; i = i + 1) begin
            nb = ($random & 3) == 0;     bi = $random;
            ns = ($random & 3) == 0;     si = $random;
            set(nb, bi, ns, si);
            idle($random & 3);
        end

        // like real traffic: mostly nothing, now and then one side moves,
        // empties, or comes back; the index wires keep random junk when empty
        test_name = "random realistic";
        nb = 0; bi = 100; ns = 0; si = 120;
        for (i = 0; i < 20000; i = i + 1) begin
            r = $random; if (r < 0) r = -r;
            mode = r % 10;
            if (mode == 0)      begin nb = ~nb; bi = $random; end        // bid side empties / returns
            else if (mode == 1) begin ns = ~ns; si = $random; end        // ask side empties / returns
            else if (mode == 2) bi = $random;                            // bid index moves
            else if (mode == 3) si = $random;                            // ask index moves
            else if (mode == 4) begin bi = $random; si = $random; end    // both move
            set(nb, bi, ns, si);
        end
        idle(4);

        $display("----------------------------------------------");
        $display("tob testbench: %0d clocks checked, %0d changes expected", cycles, updates);
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
