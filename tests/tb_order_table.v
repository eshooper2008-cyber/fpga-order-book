`timescale 1ns/1ps
// Self-checking testbench for order_table.v (the open-order memory).
// Plain Verilog, so it runs on EDA Playground or any simulator.
//
// The testbench keeps its own copy of the order table (the "model"). For every
// message it sends, the model works out which change(s) order_table should
// output, and a monitor compares them with what actually comes out.
//
// Expected outputs, one clock after the message:
//   A add      +qty at price                         (change_add = 1)
//   E execute  -qty at the order's price             (change_add = 0)
//   X cancel   -qty at the order's price             (change_add = 0)
//   D delete   -all remaining shares                 (change_add = 0)
//   U replace  -old shares at old price, then on the NEXT clock
//              +new qty at new price, same side
//   E/X/D/U on an order that isn't in the table -> not_found

module tb_order_table;

    localparam [7:0] T_ADD = 8'h41, T_EXEC = 8'h45, T_CANCEL = 8'h58,
                     T_DELETE = 8'h44, T_REPLACE = 8'h55;
    localparam [7:0] BUY = 8'h42, SELL = 8'h53;

    // ---------------------------------------------------------------- DUT
    reg         clk = 0;
    reg         valid = 0;
    reg  [7:0]  msg_type = 0;
    reg  [31:0] ID = 0;
    reg  [7:0]  side = 0;
    reg  [31:0] qty = 0;
    reg  [31:0] price = 0;
    reg  [31:0] new_ID = 0;
    wire        change_valid, change_side, change_add, not_found;
    wire [31:0] change_price, change_qty;

    order_table dut (
        .clk(clk), .valid(valid), .msg_type(msg_type), .ID(ID), .side(side),
        .qty(qty), .price(price), .new_ID(new_ID),
        .change_valid(change_valid), .change_side(change_side),
        .change_price(change_price), .change_qty(change_qty),
        .change_add(change_add), .not_found(not_found)
    );

    always #5 clk = ~clk;   // 10 ns clock

    // ---------------------------------------------------------------- model
    // The testbench's own order table, indexed by the low 8 bits of the ID
    // (the same way order_table does it).
    reg        m_used  [0:255];
    reg [7:0]  m_side  [0:255];
    reg [31:0] m_price [0:255];
    reg [31:0] m_qty   [0:255];
    integer    m_count = 0;      // open orders

    // ---------------------------------------------------------------- scoreboard
    // Queue of outputs we expect, in order.
    reg        exp_nf    [0:16383];   // 1 = expect not_found
    reg        exp_side  [0:16383];
    reg [31:0] exp_price [0:16383];
    reg [31:0] exp_qty   [0:16383];
    reg        exp_add   [0:16383];
    integer wr = 0, rd = 0;
    integer errors = 0;
    integer msgs = 0;

    task expect_change(input s, input [31:0] p, input [31:0] q, input a);
        begin
            exp_nf[wr] = 0; exp_side[wr] = s; exp_price[wr] = p;
            exp_qty[wr] = q; exp_add[wr] = a;
            wr = wr + 1;
        end
    endtask

    task expect_not_found;
        begin
            exp_nf[wr] = 1; wr = wr + 1;
        end
    endtask

    // Monitor: check every output just after each clock edge.
    always @(posedge clk) begin
        #1;
        if (change_valid && not_found) begin
            $display("  ERROR t=%0t: change_valid and not_found both high", $time);
            errors = errors + 1;
        end
        else if (change_valid || not_found) begin
            if (rd == wr) begin
                $display("  ERROR t=%0t: unexpected output (valid=%b nf=%b side=%b price=%0d qty=%0d add=%b)",
                         $time, change_valid, not_found, change_side, change_price, change_qty, change_add);
                errors = errors + 1;
            end
            else begin
                if (exp_nf[rd]) begin
                    if (!not_found) begin
                        $display("  ERROR t=%0t: expected not_found, got change (side=%b price=%0d qty=%0d add=%b)",
                                 $time, change_side, change_price, change_qty, change_add);
                        errors = errors + 1;
                    end
                end
                else begin
                    if (!change_valid) begin
                        $display("  ERROR t=%0t: expected change, got not_found", $time);
                        errors = errors + 1;
                    end
                    else if (change_side  !== exp_side[rd]  || change_price !== exp_price[rd] ||
                             change_qty   !== exp_qty[rd]   || change_add   !== exp_add[rd]) begin
                        $display("  ERROR t=%0t: got side=%b price=%0d qty=%0d add=%b, expected side=%b price=%0d qty=%0d add=%b",
                                 $time, change_side, change_price, change_qty, change_add,
                                 exp_side[rd], exp_price[rd], exp_qty[rd], exp_add[rd]);
                        errors = errors + 1;
                    end
                end
                rd = rd + 1;
            end
        end
    end

    // ---------------------------------------------------------------- send one message
    // Updates the model, queues the expected output(s), then drives the inputs
    // for one clock. There is always at least one idle clock after a message
    // (real messages are 18 clocks apart; replace needs the next clock free).
    task send(input [7:0] t, input [31:0] id, input [7:0] s,
              input [31:0] q, input [31:0] p, input [31:0] nid);
        reg [7:0] a, na;
        reg [7:0] old_side;
        begin
            a  = id[7:0];
            na = nid[7:0];
            case (t)
                T_ADD: begin
                    if (!m_used[a]) m_count = m_count + 1;
                    m_used[a] = 1; m_side[a] = s; m_price[a] = p; m_qty[a] = q;
                    expect_change(s == SELL, p, q, 1'b1);
                end
                T_EXEC, T_CANCEL: begin
                    if (!m_used[a]) expect_not_found;
                    else begin
                        expect_change(m_side[a] == SELL, m_price[a], q, 1'b0);
                        if (m_qty[a] == q) begin
                            m_used[a] = 0; m_count = m_count - 1;
                        end
                        else m_qty[a] = m_qty[a] - q;
                    end
                end
                T_DELETE: begin
                    if (!m_used[a]) expect_not_found;
                    else begin
                        expect_change(m_side[a] == SELL, m_price[a], m_qty[a], 1'b0);
                        m_used[a] = 0; m_count = m_count - 1;
                    end
                end
                T_REPLACE: begin
                    if (!m_used[a]) expect_not_found;
                    else begin
                        old_side = m_side[a];
                        expect_change(old_side == SELL, m_price[a], m_qty[a], 1'b0);  // remove old
                        expect_change(old_side == SELL, p, q, 1'b1);                  // add new (next clock)
                        m_used[a] = 0; m_count = m_count - 1;
                        if (!m_used[na]) m_count = m_count + 1;
                        m_used[na] = 1; m_side[na] = old_side; m_price[na] = p; m_qty[na] = q;
                    end
                end
                default: ;   // unknown type: nothing should happen
            endcase

            @(negedge clk);
            valid = 1; msg_type = t; ID = id; side = s; qty = q; price = p; new_ID = nid;
            @(negedge clk);
            valid = 0;
            msgs = msgs + 1;
        end
    endtask

    task idle(input integer n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) @(negedge clk);
        end
    endtask

    // Wait for everything queued to come out, then report the test.
    task finish_test(input [8*40-1:0] name, input integer errors_before);
        begin
            idle(4);
            if (rd != wr) begin
                $display("  ERROR: %0d expected output(s) never appeared", wr - rd);
                errors = errors + (wr - rd);
                rd = wr;
            end
            if (errors == errors_before) $display("PASS  %0s", name);
            else                         $display("FAIL  %0s", name);
        end
    endtask

    // Compare the DUT's memory with the model, slot by slot.
    task check_table;
        integer k;
        reg [71:0] want;
        begin
            for (k = 0; k < 256; k = k + 1) begin
                want = m_used[k] ? {m_side[k], m_price[k], m_qty[k]} : 72'd0;
                if (dut.mem[k] !== want) begin
                    $display("  ERROR: mem[%0d] = %h, expected %h", k, dut.mem[k], want);
                    errors = errors + 1;
                end
            end
        end
    endtask

    // ---------------------------------------------------------------- random helpers
    function [31:0] rnd(input integer n);   // 0 .. n-1
        rnd = {$random} % n;
    endfunction

    function [7:0] pick_used(input dummy);   // a random slot that holds an order (m_count > 0)
        reg [7:0] k;
        begin
            k = rnd(256);
            while (!m_used[k]) k = k + 1;
            pick_used = k;
        end
    endfunction

    function [7:0] pick_free(input dummy);   // a random empty slot (m_count < 256)
        reg [7:0] k;
        begin
            k = rnd(256);
            while (m_used[k]) k = k + 1;
            pick_free = k;
        end
    endfunction

    // ---------------------------------------------------------------- tests
    integer e0, n, op;
    reg [7:0] a, b;
    reg [31:0] q;

    initial begin
        for (n = 0; n < 256; n = n + 1) m_used[n] = 0;
        idle(2);

        // 1. Add a buy and a sell
        e0 = errors;
        send(T_ADD, 32'd1, BUY,  32'd100, 32'd501000, 0);
        send(T_ADD, 32'd2, SELL, 32'd50,  32'd502500, 0);
        check_table;
        finish_test("add buy and sell", e0);

        // 2. Execute part, then the rest (slot must be cleared)
        e0 = errors;
        send(T_EXEC, 32'd1, 0, 32'd30, 0, 0);    // 100 -> 70
        send(T_EXEC, 32'd1, 0, 32'd70, 0, 0);    // 70 -> 0, cleared
        send(T_EXEC, 32'd1, 0, 32'd10, 0, 0);    // gone -> not_found
        check_table;
        finish_test("execute partial then full", e0);

        // 3. Cancel part, then the rest
        e0 = errors;
        send(T_CANCEL, 32'd2, 0, 32'd20, 0, 0);  // 50 -> 30
        send(T_CANCEL, 32'd2, 0, 32'd30, 0, 0);  // 30 -> 0, cleared
        send(T_CANCEL, 32'd2, 0, 32'd5,  0, 0);  // gone -> not_found
        check_table;
        finish_test("cancel partial then full", e0);

        // 4. Delete outputs all remaining shares and clears the slot
        e0 = errors;
        send(T_ADD,    32'd3, SELL, 32'd400, 32'd499900, 0);
        send(T_EXEC,   32'd3, 0,    32'd150, 0, 0);          // 400 -> 250
        send(T_DELETE, 32'd3, 0,    0,       0, 0);          // -250
        send(T_DELETE, 32'd3, 0,    0,       0, 0);          // not_found
        check_table;
        finish_test("delete", e0);

        // 5. Replace: remove old, add new on the next clock, keep the side
        e0 = errors;
        send(T_ADD,     32'd4, BUY, 32'd100, 32'd500000, 0);
        send(T_REPLACE, 32'd4, 0,   32'd80,  32'd501000, 32'd9);  // side input is 0 on purpose
        send(T_EXEC,    32'd9, 0,   32'd10,  0, 0);               // new ID works
        send(T_EXEC,    32'd4, 0,   32'd10,  0, 0);               // old ID gone
        check_table;
        finish_test("replace keeps side, two outputs", e0);

        // 6. Replace a sell into the same ID
        e0 = errors;
        send(T_ADD,     32'd5, SELL, 32'd60, 32'd510000, 0);
        send(T_REPLACE, 32'd5, 0,    32'd90, 32'd509000, 32'd5);
        check_table;
        finish_test("replace into same ID", e0);

        // 7. Every type on an order that doesn't exist
        e0 = errors;
        send(T_EXEC,    32'd77, 0, 32'd1, 0, 0);
        send(T_CANCEL,  32'd77, 0, 32'd1, 0, 0);
        send(T_DELETE,  32'd77, 0, 0,     0, 0);
        send(T_REPLACE, 32'd77, 0, 32'd1, 32'd1, 32'd78);
        check_table;
        finish_test("unknown order -> not_found", e0);

        // 8. Max values
        e0 = errors;
        send(T_ADD,  32'd200, SELL, 32'hFFFFFFFF, 32'hFFFFFFFF, 0);
        send(T_EXEC, 32'd200, 0,    32'hFFFFFFFE, 0, 0);      // leaves 1
        check_table;
        send(T_DELETE, 32'd200, 0, 0, 0, 0);
        check_table;
        finish_test("max values", e0);

        // 9. Nothing happens while valid is low, or for an unknown type
        e0 = errors;
        valid = 0; msg_type = T_ADD; ID = 32'd50; side = BUY; qty = 32'd5; price = 32'd5;
        idle(20);
        send(8'h00, 32'd50, BUY, 32'd5, 32'd5, 0);
        send(8'h5A, 32'd50, BUY, 32'd5, 32'd5, 0);
        check_table;
        finish_test("idle and unknown types: no output", e0);

        // 10. 3000 random messages against the model
        e0 = errors;
        for (n = 0; n < 3000; n = n + 1) begin
            op = rnd(100);
            if (m_count == 0 || (op < 35 && m_count < 200)) begin
                a = pick_free(0);
                send(T_ADD, {rnd(1 << 24), a}, rnd(2) ? SELL : BUY,
                     rnd(1000) + 1, rnd(100000) + 400000, 0);
            end
            else if (op < 50) begin
                a = pick_used(0); q = rnd(m_qty[a]) + 1;
                send(T_EXEC, {24'd0, a}, 0, q, 0, 0);
            end
            else if (op < 65) begin
                a = pick_used(0); q = rnd(m_qty[a]) + 1;
                send(T_CANCEL, {24'd0, a}, 0, q, 0, 0);
            end
            else if (op < 78) begin
                a = pick_used(0);
                send(T_DELETE, {24'd0, a}, 0, 0, 0, 0);
            end
            else if (op < 93) begin
                a = pick_used(0);
                b = rnd(4) == 0 ? a : pick_free(0);
                send(T_REPLACE, {24'd0, a}, 0, rnd(1000) + 1, rnd(100000) + 400000, {24'd0, b});
            end
            else begin
                if (m_count < 256) begin
                    a = pick_free(0);   // order that doesn't exist
                    send(T_EXEC, {24'd0, a}, 0, 32'd1, 0, 0);
                end
            end
            idle(rnd(3));   // 0-2 extra idle clocks
        end
        check_table;
        finish_test("3000 random messages vs model", e0);

        // ------------------------------------------------------------ summary
        $display("--------------------------------------------");
        if (errors == 0)
            $display("ALL TESTS PASSED  (%0d messages, %0d outputs checked)", msgs, rd);
        else
            $display("%0d ERROR(S)", errors);
        $finish;
    end

endmodule
