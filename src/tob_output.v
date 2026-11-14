module tob(
    input clk,
    input [7:0] buy_index,
    input [7:0] sell_index,
    input no_sell,
    input no_buy,
    output reg best_change
);

reg [7:0] old_buy = 8'd0;
reg [7:0] old_sell = 8'd0;
reg old_no_sell = 1'd1;
reg old_no_buy = 1'd1;



always@(posedge clk) begin
    best_change <= 1'd0;

    if(no_sell != old_no_sell || no_buy != old_no_buy) begin
            best_change<=1'd1;
            old_no_sell <= no_sell;
            old_no_buy <= no_buy;
            old_buy <= buy_index;
            old_sell <= sell_index;
    end
    else begin
        if(buy_index != old_buy || sell_index != old_sell) begin
            best_change <= 1'd1;
            old_buy <= buy_index;
            old_sell <= sell_index;
        end
    end
end
endmodule
