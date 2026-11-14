// ---------------------------------------------------------------------------
// tb_top.v  --  self-checking end-to-end testbench for top
//
// Written by Claude only to test Elliott's top module (src/top.v) and the
// modules it connects. Plain Verilog-2005: run in EDA Playground (Icarus
// Verilog) with every file from src/ in the design pane, or with
//     iverilog -g2005 -o sim tests/tb_top.v src/*.v && vvp sim
//
// What it does
//   Sends 18-byte messages into top one byte per clock and keeps its own
//   model of the whole book (order table, price levels, best bid and ask).
//   After every message it works out, clock by clock, when best_change must
//   pulse and what the best bid and ask must be, and checks top against that.
//
// Timing the model expects (the edge that captures the last byte of a message
// is called edge 0):
//   edge 1   order_table outputs the first price-level change
//   edge 2   price_levels updates its bitmaps
//   edge 3   best_change is high if the best bid or ask changed
//   edge 4   second change of a replace message (remove old, then add new)
//   edge 6   the best bid and ask have settled, so they are compared
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_top;

    parameter BASE        = 1000000;   // lowest price price_levels covers
    parameter TICK        = 100;       // price step per level
    parameter MAXC        = 300000;    // longest run, in clock edges
    parameter RANDOM_MSGS = 3000;

    reg        clk   = 1'b0;
    reg        valid = 1'b0;
    reg  [7:0] data  = 8'd0;
    wire [7:0] buy_index;
    wire [7:0] sell_index;
    wire       no_sell;
    wire       no_buy;
    wire       best_change;

    top dut (
        .clk         (clk),
        .valid       (valid),
        .data        (data),
        .buy_index   (buy_index),
        .sell_index  (sell_index),
        .no_sell     (no_sell),
        .no_buy      (no_buy),
        .best_change (best_change)
    );

    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // The model: order table, price levels, last reported best bid / ask
    // ------------------------------------------------------------------
    integer     ot_used  [0:255];
    reg [7:0]   ot_side  [0:255];
    integer     ot_price [0:255];
    integer     ot_qty   [0:255];
    integer     bqty     [0:255];      // shares at every buy level
    integer     sqty     [0:255];      // shares at every sell level

    reg         rep_nb, rep_ns;        // last reported best bid / ask
    integer     rep_bi, rep_si;
    reg         cur_nb, cur_ns;        // best bid / ask right now
    integer     cur_bi, cur_si;

    reg         exp_pulse [0:MAXC];    // clock edge -> best_change must be 1
    reg [18:0]  chk_word  [0:MAXC];    // clock edge -> {check, no_buy, no_sell, bid, ask}

    integer N;                         // edge that captures the last byte
    integer ec        = 0;             // clock edges so far
    integer errors    = 0;
    integer msgs      = 0;
    integer exp_pulses = 0, got_pulses = 0;
    integer exp_nf = 0,  got_nf = 0;
    integer exp_oor = 0, got_oor = 0;
    integer got_err = 0;
    integer i;
    reg [8*32-1:0] test_name = "start";

    function integer rnd;              // 0 .. n-1
        input integer n;
        integer r;
        begin
            r = $random;
            r = r & 32'h7fffffff;
            rnd = r % n;
        end
    endfunction

    function integer px;               // price of a level
        input integer lvl;
        begin
            px = BASE + lvl * TICK;
        end
    endfunction

    task compute_state;
        integer k;
        begin
            cur_nb = 1'b1; cur_ns = 1'b1; cur_bi = 0; cur_si = 0;
            for (k = 0; k < 256; k = k + 1)
                if (bqty[k] > 0) begin cur_nb = 1'b0; cur_bi = k; end     // highest buy
            for (k = 255; k >= 0; k = k - 1)
                if (sqty[k] > 0) begin cur_ns = 1'b0; cur_si = k; end     // lowest sell
        end
    endtask

    // One price-level change, as order_table sends it to price_levels
    task apply_change;
        input        sidebit;          // 0 buy, 1 sell
        input integer p;
        input integer q;
        input        add;
        input integer ev;              // 0 = first change of a message, 1 = second
        integer idx;
        reg changed;
        begin
            if (p < BASE || p > BASE + 255 * TICK) begin
                exp_oor = exp_oor + 1;                      // outside the window: ignored
            end else begin
                idx = (p - BASE) / TICK;
                if (sidebit == 1'b0) bqty[idx] = add ? bqty[idx] + q : bqty[idx] - q;
                else                 sqty[idx] = add ? sqty[idx] + q : sqty[idx] - q;
            end
            compute_state;
            changed = (cur_nb !== rep_nb) || (cur_ns !== rep_ns) ||
                      (!cur_nb && cur_bi != rep_bi) || (!cur_ns && cur_si != rep_si);
            if (changed) begin
                exp_pulse[N + 3 + ev] = 1'b1;
                exp_pulses = exp_pulses + 1;
                rep_nb = cur_nb; rep_ns = cur_ns; rep_bi = cur_bi; rep_si = cur_si;
            end
        end
    endtask

    task model_message;
        input [7:0]  t;
        input [31:0] id;
        input [7:0]  s;
        input [31:0] q;
        input [31:0] p;
        input [31:0] nid;
        integer slot, nslot, stq, stp;
        reg [7:0] sts;
        reg sb;
        begin
            slot = id[7:0]; nslot = nid[7:0];
            case (t)
                8'h41: begin                                // add
                    ot_used[slot] = 1; ot_side[slot] = s; ot_price[slot] = p; ot_qty[slot] = q;
                    apply_change((s == 8'h42) ? 1'b0 : 1'b1, p, q, 1'b1, 0);
                end
                8'h45, 8'h58: begin                         // execute, cancel
                    if (!ot_used[slot]) exp_nf = exp_nf + 1;
                    else begin
                        sb = (ot_side[slot] == 8'h42) ? 1'b0 : 1'b1;
                        stp = ot_price[slot]; stq = ot_qty[slot];
                        if (stq == q) ot_used[slot] = 0; else ot_qty[slot] = stq - q;
                        apply_change(sb, stp, q, 1'b0, 0);
                    end
                end
                8'h44: begin                                // delete
                    if (!ot_used[slot]) exp_nf = exp_nf + 1;
                    else begin
                        sb = (ot_side[slot] == 8'h42) ? 1'b0 : 1'b1;
                        stp = ot_price[slot]; stq = ot_qty[slot];
                        ot_used[slot] = 0;
                        apply_change(sb, stp, stq, 1'b0, 0);
                    end
                end
                8'h55: begin                                // replace
                    if (!ot_used[slot]) exp_nf = exp_nf + 1;
                    else begin
                        sts = ot_side[slot]; sb = (sts == 8'h42) ? 1'b0 : 1'b1;
                        stp = ot_price[slot]; stq = ot_qty[slot];
                        ot_used[slot] = 0;
                        ot_used[nslot] = 1; ot_side[nslot] = sts;
                        ot_price[nslot] = p; ot_qty[nslot] = q;
                        apply_change(sb, stp, stq, 1'b0, 0);
                        apply_change(sb, p, q, 1'b1, 1);
                    end
                end
                default: ;
            endcase
            compute_state;
            chk_word[N + 6] = {1'b1, cur_nb, cur_ns, cur_bi[7:0], cur_si[7:0]};
        end
    endtask

    // ------------------------------------------------------------------
    // Checking: runs after every clock edge
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        ec = ec + 1;
        #1;
        if (best_change !== exp_pulse[ec]) begin
            errors = errors + 1;
            if (errors <= 20)
                $display("FAIL [%0s] edge %0d: best_change=%b, expected %b",
                    test_name, ec, best_change, exp_pulse[ec]);
        end
        if (best_change === 1'b1) got_pulses = got_pulses + 1;

        if (chk_word[ec][18]) begin
            if (no_buy !== chk_word[ec][17] || no_sell !== chk_word[ec][16] ||
                (!chk_word[ec][17] && buy_index  !== chk_word[ec][15:8]) ||
                (!chk_word[ec][16] && sell_index !== chk_word[ec][7:0])) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("FAIL [%0s] edge %0d: best bid/ask: got no_buy=%b buy=%0d no_sell=%b sell=%0d, expected no_buy=%b buy=%0d no_sell=%b sell=%0d",
                        test_name, ec, no_buy, buy_index, no_sell, sell_index,
                        chk_word[ec][17], chk_word[ec][15:8], chk_word[ec][16], chk_word[ec][7:0]);
            end
        end

        if (dut.not_found    === 1'b1) got_nf  = got_nf  + 1;
        if (dut.out_of_range === 1'b1) got_oor = got_oor + 1;
        if (dut.error        === 1'b1) got_err = got_err + 1;
    end

    // ------------------------------------------------------------------
    // Stimulus
    // ------------------------------------------------------------------
    task send_msg;
        input [7:0]  t;
        input [31:0] id;
        input [7:0]  s;
        input [31:0] q;
        input [31:0] p;
        input [31:0] nid;
        reg [143:0] m;
        integer j;
        begin
            m = {t, id, s, q, p, nid};
            for (j = 17; j >= 0; j = j - 1) begin
                @(negedge clk);
                valid = 1'b1;
                data  = m[j*8 +: 8];
            end
            N = ec + 1;                    // the next edge captures the last byte
            msgs = msgs + 1;
            model_message(t, id, s, q, p, nid);
        end
    endtask

    task idle;                             // valid low, junk on data
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                @(negedge clk);
                valid = 1'b0;
                data  = $random;
            end
        end
    endtask

    task add_o;
        input integer slot; input [7:0] sd; input integer price; input integer q;
        begin send_msg(8'h41, slot, sd, q, price, 0); end
    endtask
    task exec_o;
        input integer slot; input integer q;
        begin send_msg(8'h45, slot, 8'd0, q, 0, 0); end
    endtask
    task cancel_o;
        input integer slot; input integer q;
        begin send_msg(8'h58, slot, 8'd0, q, 0, 0); end
    endtask
    task del_o;
        input integer slot;
        begin send_msg(8'h44, slot, 8'd0, 0, 0, 0); end
    endtask
    task repl_o;
        input integer slot; input integer nslot; input integer price; input integer q;
        begin send_msg(8'h55, slot, 8'd0, q, price, nslot); end
    endtask

    // random helpers that look at the model
    function integer pick_active;
        input integer dummy;
        integer s, k;
        begin
            pick_active = -1;
            s = rnd(256);
            for (k = 0; k < 256; k = k + 1)
                if (pick_active < 0 && ot_used[(s + k) % 256]) pick_active = (s + k) % 256;
        end
    endfunction

    function integer pick_free;
        input integer dummy;
        integer s, k;
        begin
            pick_free = -1;
            s = rnd(256);
            for (k = 0; k < 256; k = k + 1)
                if (pick_free < 0 && !ot_used[(s + k) % 256]) pick_free = (s + k) % 256;
        end
    endfunction

    function integer n_active;
        input integer dummy;
        integer k;
        begin
            n_active = 0;
            for (k = 0; k < 256; k = k + 1) if (ot_used[k]) n_active = n_active + 1;
        end
    endfunction

    function integer gen_price;            // mostly inside the window, sometimes not
        input integer sidebit;             // 0 buy, 1 sell
        integer r;
        begin
            r = rnd(100);
            if (r < 62) begin                                               // buys low, sells high
                if (sidebit == 0) gen_price = px(90 + rnd(41));
                else              gen_price = px(125 + rnd(41));
            end
            else if (r < 88) gen_price = px(rnd(256));                      // anywhere in the window
            else if (r < 92) gen_price = BASE - TICK * (1 + rnd(50));       // below the window
            else if (r < 95) gen_price = BASE + 255 * TICK + 1 + rnd(5000); // above the window
            else             gen_price = px(rnd(256)) + rnd(TICK);          // between two levels
        end
    endfunction

    function [31:0] make_id;
        input integer slot;
        begin
            make_id = (rnd(16777216) << 8) | slot;
        end
    endfunction

    integer m, r, slot, nslot, stq, q, sel, na;
    reg [7:0] sd;

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            ot_used[i] = 0; ot_side[i] = 8'd0; ot_price[i] = 0; ot_qty[i] = 0;
            bqty[i] = 0; sqty[i] = 0;
        end
        for (i = 0; i <= MAXC; i = i + 1) begin
            exp_pulse[i] = 1'b0;
            chk_word[i]  = 19'd0;
        end
        rep_nb = 1'b1; rep_ns = 1'b1; rep_bi = 0; rep_si = 0;
        N = 0;

        idle(6);

        // ---------------- directed tests ----------------
        test_name = "bid appears";
        add_o(1, 8'h42, px(110), 100);                 idle(2);
        test_name = "ask appears";
        add_o(2, 8'h53, px(122), 50);                  idle(2);
        test_name = "bid improves";
        add_o(3, 8'h42, px(114), 10);                  idle(2);
        test_name = "more shares on the best level";
        add_o(4, 8'h42, px(114), 5);                   idle(2);
        test_name = "partial cancel";
        cancel_o(3, 3);                                idle(2);
        test_name = "execute rest of an order";
        exec_o(3, 7);                                  idle(2);
        test_name = "best level empties";
        del_o(4);                                      idle(2);
        test_name = "replace moves the ask";
        repl_o(2, 5, px(118), 20);                     idle(2);
        test_name = "price below the window";
        add_o(6, 8'h42, BASE - TICK, 10);              idle(2);
        test_name = "price above the window";
        add_o(7, 8'h53, BASE + 256 * TICK, 10);        idle(2);
        test_name = "unknown order id";
        exec_o(99, 5);                                 idle(2);
        del_o(98);                                     idle(2);
        cancel_o(97, 1);                               idle(2);
        repl_o(96, 95, px(100), 1);                    idle(2);
        test_name = "worse levels, edges of the window";
        add_o(8, 8'h42, px(0), 1);                     idle(2);
        add_o(9, 8'h53, px(255), 1);                   idle(2);
        test_name = "replace into the same slot";
        repl_o(5, 5, px(116), 9);                      idle(2);
        test_name = "replace out of the window";
        repl_o(1, 10, BASE - 5 * TICK, 4);             idle(2);
        test_name = "back to back, no gaps";
        add_o(11, 8'h42, px(130), 5);
        add_o(12, 8'h53, px(100), 5);
        del_o(11);
        del_o(12);
        idle(2);
        test_name = "same price, both sides";
        add_o(13, 8'h42, px(140), 5);
        add_o(14, 8'h53, px(140), 5);                  idle(2);
        del_o(13);  del_o(14);                         idle(3);

        // ---------------- random traffic ----------------
        // (the book alternates between a thin phase with few orders, where the best
        // bid and ask change often, and a deeper phase)
        test_name = "random traffic";
        for (m = 0; m < RANDOM_MSGS; m = m + 1) begin
            na = n_active(0);
            r  = rnd(100);
            if (na == 0 || (r < 34 && na < ((m % 600 < 300) ? 8 : 60))) begin                       // add
                slot = pick_free(0);
                sd   = (rnd(2) == 0) ? 8'h42 : 8'h53;
                send_msg(8'h41, make_id(slot), sd, 1 + rnd(400), gen_price((sd == 8'h42) ? 0 : 1), 0);
            end else if (r < 46) begin                                       // execute
                slot = pick_active(0);  stq = ot_qty[slot];
                q = (rnd(100) < 40) ? stq : 1 + rnd(stq);
                send_msg(8'h45, make_id(slot), 8'd0, q, 0, 0);
            end else if (r < 60) begin                                       // cancel
                slot = pick_active(0);  stq = ot_qty[slot];
                q = (rnd(100) < 40) ? stq : 1 + rnd(stq);
                send_msg(8'h58, make_id(slot), 8'd0, q, 0, 0);
            end else if (r < 74) begin                                       // delete
                slot = pick_active(0);
                send_msg(8'h44, make_id(slot), 8'd0, 0, 0, 0);
            end else if (r < 92) begin                                       // replace
                slot = pick_active(0);
                nslot = (rnd(100) < 25) ? slot : pick_free(0);
                if (nslot < 0) nslot = slot;
                send_msg(8'h55, make_id(slot), 8'd0, 1 + rnd(300), gen_price((ot_side[slot] == 8'h42) ? 0 : 1), make_id(nslot));
            end else begin                                                   // unknown order
                slot = pick_free(0);
                sel  = rnd(4);
                case (sel)
                    0: send_msg(8'h45, make_id(slot), 8'd0, 1 + rnd(50), 0, 0);
                    1: send_msg(8'h58, make_id(slot), 8'd0, 1 + rnd(50), 0, 0);
                    2: send_msg(8'h44, make_id(slot), 8'd0, 0, 0, 0);
                    default: send_msg(8'h55, make_id(slot), 8'd0, 1 + rnd(50), gen_price(rnd(2)), make_id(pick_free(0)));
                endcase
            end
            idle(rnd(4));                                                    // 0 to 3 idle clocks
        end
        idle(2);

        // ---------------- empty the book ----------------
        test_name = "empty the book";
        slot = pick_active(0);
        while (slot >= 0) begin
            del_o(slot);
            idle(rnd(2));
            slot = pick_active(0);
        end
        idle(12);

        // ---------------- result ----------------
        if (got_nf  !== exp_nf)  begin errors = errors + 1; $display("FAIL: not_found pulses %0d, expected %0d", got_nf, exp_nf); end
        if (got_oor !== exp_oor) begin errors = errors + 1; $display("FAIL: out_of_range pulses %0d, expected %0d", got_oor, exp_oor); end
        if (got_err !== 0)       begin errors = errors + 1; $display("FAIL: price_levels error flag was high %0d times", got_err); end

        $display("----------------------------------------------");
        $display("top testbench: %0d messages, %0d clocks, %0d best_change pulses checked", msgs, ec, exp_pulses);
        $display("not_found %0d, out_of_range %0d (all as expected)", exp_nf, exp_oor);
        $display("best_change is high 3 clocks after the edge that captures the last byte of a message");
        if (errors == 0) $display("PASS: no errors");
        else             $display("FAIL: %0d errors", errors);
        $display("----------------------------------------------");
        $finish;
    end

    initial begin
        #200000000;
        $display("FAIL: testbench timed out");
        $finish;
    end

endmodule
