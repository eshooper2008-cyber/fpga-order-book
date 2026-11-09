// Testbench for price_levels (written by Claude to test Elliott's code).
//
// Self-checking, plain Verilog-2005. It keeps its own model of the total shares
// at every bid and ask level. After every clock it checks:
//   - dut.buy_qty_map[i] / dut.sell_qty_map[i] equal the model totals
//   - each bitmap bit is 1 exactly when that level's total is above zero
//
// Assumes price_levels has:
//   parameter BASE_PRICE ($100.00); TICK (100) and LEVELS (255) keep their defaults
//   inputs  clk, change_valid, change_side (0 buy / 1 sell), change_price,
//           change_qty, change_add (1 add / 0 remove)
//   outputs buy_levels[255:0], sell_levels[255:0], out_of_range, error
//   internal arrays named buy_qty_map and sell_qty_map (one total per level)
//
// Run:  iverilog -g2005 -o sim tests/tb_price_levels.v src/price_levels.v && vvp sim

`timescale 1ns/1ps

module tb_price_levels;

parameter N          = 256;
parameter BASE_PRICE = 1000000;  // $100.00 (4 implied decimals)
parameter TICK       = 100;      // $0.01

reg         clk = 1'b0;
reg         change_valid = 1'b0;
reg         change_side  = 1'b0;
reg  [31:0] change_price = 32'd0;
reg  [31:0] change_qty   = 32'd0;
reg         change_add   = 1'b0;
wire [N-1:0] bid_bitmap;
wire [N-1:0] ask_bitmap;
wire         out_of_range;
wire         error;

always #5 clk = ~clk;

price_levels #(.BASE_PRICE(BASE_PRICE)) dut (
    .clk(clk),
    .change_valid(change_valid),
    .change_side(change_side),
    .change_price(change_price),
    .change_qty(change_qty),
    .change_add(change_add),
    .buy_levels(bid_bitmap),
    .sell_levels(ask_bitmap),
    .out_of_range(out_of_range),
    .error(error)
);

// ---------------------------------------------------------------- model
reg [31:0] m_bid [0:N-1];
reg [31:0] m_ask [0:N-1];

integer errors = 0;
integer changes = 0;
integer checks = 0;
integer i;

// Compare the whole DUT state with the model. Called one clock after a change.
task check_all;
    integer lv;
    begin
        checks = checks + 1;
        for (lv = 0; lv < N; lv = lv + 1) begin
            if (dut.buy_qty_map[lv] !== m_bid[lv]) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("FAIL t=%0t buy_qty_map[%0d] = %0d, expected %0d", $time, lv, dut.buy_qty_map[lv], m_bid[lv]);
            end
            if (dut.sell_qty_map[lv] !== m_ask[lv]) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("FAIL t=%0t sell_qty_map[%0d] = %0d, expected %0d", $time, lv, dut.sell_qty_map[lv], m_ask[lv]);
            end
            if (bid_bitmap[lv] !== (m_bid[lv] != 32'd0)) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("FAIL t=%0t bid_bitmap[%0d] = %b, expected %b (total %0d)", $time, lv, bid_bitmap[lv], (m_bid[lv] != 32'd0), m_bid[lv]);
            end
            if (ask_bitmap[lv] !== (m_ask[lv] != 32'd0)) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("FAIL t=%0t ask_bitmap[%0d] = %b, expected %b (total %0d)", $time, lv, ask_bitmap[lv], (m_ask[lv] != 32'd0), m_ask[lv]);
            end
        end
    end
endtask

// Present one price-level change for exactly one clock, update the model, and
// check the DUT after the clock edge. Calling drive again straight away gives
// back-to-back changes on consecutive clocks (like a replace).
task drive;
    input        side;
    input [31:0] level;
    input [31:0] qty;
    input        add;
    begin
        change_valid = 1'b1;
        change_side  = side;
        change_price = BASE_PRICE + level * TICK;
        change_qty   = qty;
        change_add   = add;
        if (side == 1'b0)
            m_bid[level] = add ? (m_bid[level] + qty) : (m_bid[level] - qty);
        else
            m_ask[level] = add ? (m_ask[level] + qty) : (m_ask[level] - qty);
        changes = changes + 1;
        @(negedge clk);
        check_all;
        if (out_of_range !== 1'b0 || error !== 1'b0) begin
            errors = errors + 1;
            if (errors <= 20)
                $display("FAIL t=%0t out_of_range=%b error=%b after a normal in-range change", $time, out_of_range, error);
        end
    end
endtask

// A change that must be rejected: the model is NOT updated, so check_all also
// proves the DUT's totals and bitmaps did not move.
task drive_bad;
    input        side;
    input [31:0] price;
    input [31:0] qty;
    input        add;
    input        expect_range;   // 1: expect out_of_range, 0: expect error
    begin
        change_valid = 1'b1;
        change_side  = side;
        change_price = price;
        change_qty   = qty;
        change_add   = add;
        changes = changes + 1;
        @(negedge clk);
        check_all;
        if (expect_range) begin
            if (out_of_range !== 1'b1) begin
                errors = errors + 1;
                if (errors <= 20) $display("FAIL t=%0t price %0d should set out_of_range", $time, price);
            end
        end else begin
            if (error !== 1'b1) begin
                errors = errors + 1;
                if (errors <= 20) $display("FAIL t=%0t removing %0d shares should set error", $time, qty);
            end
        end
    end
endtask

// change_valid low for n clocks, with junk on the other inputs.
// Nothing should change.
task idle;
    input integer n;
    integer k;
    begin
        for (k = 0; k < n; k = k + 1) begin
            change_valid = 1'b0;
            change_side  = $random;
            change_price = BASE_PRICE + (({$random} % N) * TICK);
            change_qty   = $random;
            change_add   = $random;
            @(negedge clk);
            check_all;
        end
    end
endtask

task report;
    input [8*64-1:0] name;
    input integer errs_before;
    begin
        if (errors == errs_before) $display("  ok   %0s", name);
        else                       $display("  FAIL %0s", name);
    end
endtask

// ---------------------------------------------------------------- tests
integer e0;
integer n;
integer lv;
reg     rs;
reg     radd;
reg [31:0] rq;
reg [31:0] tot;

initial begin
    for (i = 0; i < N; i = i + 1) begin
        m_bid[i] = 32'd0;
        m_ask[i] = 32'd0;
    end

    $display("tb_price_levels: N=%0d BASE_PRICE=%0d TICK=%0d", N, BASE_PRICE, TICK);

    @(negedge clk);

    // 1. nothing happens before any change
    e0 = errors;
    idle(3);
    report("starts empty", e0);

    // 2. one add on each side
    e0 = errors;
    drive(1'b0, 32'd110, 32'd500, 1'b1);   // bid $50.10
    idle(1);
    drive(1'b1, 32'd120, 32'd300, 1'b1);   // ask $50.20
    idle(1);
    report("single add, bid and ask", e0);

    // 3. totals accumulate at one level, bit stays set until empty
    e0 = errors;
    drive(1'b0, 32'd110, 32'd200, 1'b1);   // 700
    drive(1'b0, 32'd110, 32'd50,  1'b1);   // 750
    idle(1);
    drive(1'b0, 32'd110, 32'd250, 1'b0);   // 500 left
    idle(1);
    drive(1'b0, 32'd110, 32'd499, 1'b0);   // 1 left, bit must still be 1
    idle(1);
    drive(1'b0, 32'd110, 32'd1,   1'b0);   // 0, bit must clear
    idle(2);
    report("accumulate, partial remove, full remove", e0);

    // 4. lowest and highest level on both sides
    e0 = errors;
    drive(1'b0, 32'd0,       32'd10, 1'b1);
    drive(1'b0, (N-1),   32'd20, 1'b1);
    drive(1'b1, 32'd0,       32'd30, 1'b1);
    drive(1'b1, (N-1),   32'd40, 1'b1);
    idle(1);
    drive(1'b0, 32'd0,       32'd10, 1'b0);
    drive(1'b1, (N-1),   32'd40, 1'b0);
    idle(1);
    drive(1'b0, (N-1),   32'd20, 1'b0);
    drive(1'b1, 32'd0,       32'd30, 1'b0);
    idle(1);
    report("first and last level", e0);

    // 5. bid and ask at the same price do not affect each other
    e0 = errors;
    drive(1'b0, 32'd77, 32'd100, 1'b1);
    drive(1'b1, 32'd77, 32'd60,  1'b1);
    idle(1);
    drive(1'b1, 32'd77, 32'd60,  1'b0);    // ask empties, bid must stay
    idle(1);
    drive(1'b0, 32'd77, 32'd100, 1'b0);
    idle(1);
    report("bid and ask at same price are independent", e0);

    // 6. back-to-back changes on consecutive clocks (what a replace sends)
    e0 = errors;
    drive(1'b0, 32'd50, 32'd400, 1'b1);
    idle(1);
    drive(1'b0, 32'd50, 32'd400, 1'b0);    // remove at old price ...
    drive(1'b0, 32'd60, 32'd400, 1'b1);    // ... add at new price, next clock
    idle(1);
    drive(1'b0, 32'd60, 32'd400, 1'b0);    // replace to the same price:
    drive(1'b0, 32'd60, 32'd300, 1'b1);    // remove then add at the same level
    idle(1);
    drive(1'b0, 32'd60, 32'd300, 1'b0);
    idle(1);
    report("back-to-back changes", e0);

    // 7. the maximum 32-bit quantity
    e0 = errors;
    drive(1'b1, 32'd5, 32'hFFFF_FFFF, 1'b1);
    idle(1);
    drive(1'b1, 32'd5, 32'hFFFF_FFFE, 1'b0);   // 1 left
    idle(1);
    drive(1'b1, 32'd5, 32'd1, 1'b0);
    idle(1);
    report("max quantity", e0);

    // 8. change_valid low must be ignored, whatever is on the other inputs
    e0 = errors;
    drive(1'b0, 32'd9, 32'd25, 1'b1);
    idle(10);
    drive(1'b0, 32'd9, 32'd25, 1'b0);
    idle(2);
    report("ignores inputs while change_valid is low", e0);

    // 9. random traffic against the model.
    //    Half the changes go to a small cluster of levels so the same level is
    //    hit many times; removals never take more than the level holds.
    e0 = errors;
    for (n = 0; n < 5000; n = n + 1) begin
        rs = $random;
        if ({$random} % 2 == 0) lv = 100 + ({$random} % 6);
        else                    lv = {$random} % N;
        tot  = rs ? m_ask[lv] : m_bid[lv];
        radd = $random;
        if (tot == 32'd0) radd = 1'b1;
        if (radd) begin
            rq = ({$random} % 1000) + 1;
        end else begin
            if ({$random} % 3 == 0) rq = tot;                    // remove the lot
            else                    rq = ({$random} % tot) + 1;  // remove some
        end
        drive(rs, lv, rq, radd);
        if ({$random} % 3 != 0) idle({$random} % 3);             // 0 to 2 idle clocks
    end
    report("5000 random changes vs model", e0);

    // 10. remove everything back-to-back; both bitmaps must end all zeros
    e0 = errors;
    for (lv = 0; lv < N; lv = lv + 1) begin
        if (m_bid[lv] != 32'd0) drive(1'b0, lv, m_bid[lv], 1'b0);
        if (m_ask[lv] != 32'd0) drive(1'b1, lv, m_ask[lv], 1'b0);
    end
    idle(2);
    if (bid_bitmap !== {N{1'b0}} || ask_bitmap !== {N{1'b0}}) begin
        errors = errors + 1;
        $display("FAIL bitmaps not all zero after removing everything");
    end
    report("drain book to empty", e0);

    // 11. prices outside the window are rejected and change nothing.
    //     The last valid price is BASE_PRICE + (N-1)*TICK.
    e0 = errors;
    drive_bad(1'b0, BASE_PRICE - TICK,              32'd10, 1'b1, 1'b1);  // one tick below
    drive_bad(1'b1, BASE_PRICE - 32'd1,             32'd10, 1'b1, 1'b1);  // just below
    drive_bad(1'b0, BASE_PRICE + N*TICK,            32'd10, 1'b1, 1'b1);  // one tick above
    drive_bad(1'b1, BASE_PRICE + (N+100)*TICK,      32'd10, 1'b1, 1'b1);  // well above
    drive_bad(1'b0, BASE_PRICE + 700*TICK,          32'd10, 1'b1, 1'b1);  // 700 levels up
    drive_bad(1'b1, 32'd0,                          32'd10, 1'b0, 1'b1);  // price 0, a remove
    idle(1);
    drive(1'b0, 32'd0,     32'd5, 1'b1);                                   // edges still work
    drive(1'b1, (N-1),     32'd5, 1'b1);
    drive(1'b0, 32'd0,     32'd5, 1'b0);
    drive(1'b1, (N-1),     32'd5, 1'b0);
    idle(1);
    report("out of range prices rejected", e0);

    // 12. removing more shares than a level holds sets error and changes nothing
    e0 = errors;
    drive_bad(1'b0, BASE_PRICE + 3*TICK, 32'd5, 1'b0, 1'b0);   // empty bid level
    drive_bad(1'b1, BASE_PRICE + 3*TICK, 32'd5, 1'b0, 1'b0);   // empty ask level
    drive(1'b0, 32'd3, 32'd10, 1'b1);
    drive_bad(1'b0, BASE_PRICE + 3*TICK, 32'd11, 1'b0, 1'b0);  // one too many
    drive_bad(1'b1, BASE_PRICE + 3*TICK, 32'd1,  1'b0, 1'b0);  // ask side is still empty
    idle(1);
    drive(1'b0, 32'd3, 32'd10, 1'b0);                          // exact amount still works
    idle(1);
    report("remove more than held sets error", e0);

    $display("-----");
    $display("%0d changes, %0d full-state checks, %0d errors", changes, checks, errors);
    if (errors == 0) $display("ALL TESTS PASSED");
    else             $display("TESTS FAILED");
    $finish;
end

// watchdog
initial begin
    #20000000;
    $display("FAIL timeout");
    $finish;
end

endmodule
