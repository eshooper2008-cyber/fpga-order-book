module top(

    input clk,
    input valid,
    input [7:0] data,
    output wire [7:0] buy_index,
    output wire [7:0] sell_index,
    output wire no_sell,
    output wire no_buy,
    output wire best_change


);
wire msg_valid;
wire [31:0] price;
wire [7:0] msg_type;
wire [31:0] ID;
wire [7:0] side;
wire [31:0] qty;
wire [31:0] new_ID;
wire change_valid;
wire change_side;       
wire [31:0] change_price;
wire [31:0] change_qty;
wire change_add;
wire not_found;
wire [255:0] buy_levels;   
wire [255:0] sell_levels;
wire out_of_range;
wire error;


    msg_rx msg_rx(

        .clk (clk),
        .valid (valid),
        .data (data),
        .msg_valid (msg_valid),
        .price (price),
        .msg_type (msg_type),
        .ID (ID),
        .side (side),
        .qty (qty),
        .new_ID (new_ID)
    );
    order_table order_table(
        .clk (clk),
        .valid (msg_valid),
        .msg_type (msg_type),
        .ID (ID),
        .side (side),
        .qty (qty),
        .price (price),
        .new_ID (new_ID),
        .change_valid (change_valid),
        .change_side (change_side),
        .change_price (change_price),
        .change_qty (change_qty),
        .change_add (change_add),
        .not_found (not_found)
    );
    price_levels price_levels(
        .clk (clk),
        .change_valid (change_valid),
        .change_side (change_side),
        .change_price (change_price),
        .change_qty (change_qty),
        .change_add (change_add),
        .buy_levels (buy_levels),
        .sell_levels (sell_levels),
        .out_of_range (out_of_range),
        .error (error)
    );
    best_price best_price(
        .buy_levels (buy_levels),
        .sell_levels (sell_levels),
        .buy_index (buy_index),
        .sell_index (sell_index),
        .no_sell (no_sell),
        .no_buy (no_buy)
    );
    tob_output tob_output(
        .clk (clk),
        .buy_index (buy_index),
        .sell_index (sell_index),
        .no_sell (no_sell),
        .no_buy (no_buy),
        .best_change (best_change)
    );



endmodule
