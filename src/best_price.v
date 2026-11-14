module best(
    input [255:0] buy_levels,
    input [255:0] sell_levels,
    output reg [7:0] buy_index,
    output reg [7:0] sell_index,
    output reg no_sell,
    output reg no_buy
);

integer i;

reg sell_change = 1'd1;
reg buy_change = 1'd1;

always@(*)begin
sell_change = 1'd1;
buy_change = 1'd1;
for (i=0; i<256; i=i+1) begin

    if(sell_levels[i])begin
        if(sell_change)begin
            sell_index = i;
            sell_change = 1'd0;
        end
    end
    if(buy_levels[255-i])begin
        if(buy_change)begin
            buy_index = 255-i;
            buy_change = 1'd0;
        end
    end
end


no_buy = buy_change;
no_sell = sell_change;
end
endmodule
