module price_levels(
    input clk,
    input change_valid,
    input change_side,         // 0 for buy, 1 for sell
    input [31:0] change_price,
    input [31:0] change_qty,
    input change_add,
    output reg [255:0] buy_levels,   
    output reg [255:0] sell_levels,
    output reg out_of_range,
    output reg error
);

parameter BASE_PRICE = 32'd1000000;                                // 100.00 dollar base price, max price is 102.56 dollars, min price is 100.00 dollars
parameter [7:0] LEVELS = 8'd255;                                   // 256 levels, 0.010 each level, 2.56 total range
parameter [31:0] TICK = 32'd100;                                   // 0.010 dollar levels
wire [31:0] index_price = (change_price - BASE_PRICE)/TICK;        // makes 256 indexs above some reasonable base price so that you can get 1 cent ticks
reg [31:0] sell_qty_map [255:0];                                   // maps the qty of sell orders at every 0.01 dollar level
reg [31:0] buy_qty_map [255:0];                                    // maps the qty of buy orders at every 0.01 dollar level
integer i = 0;                                                     // variable for the for loop on line 28



initial begin
    buy_levels <= 256'd0;                                          // sets the ouput to all 0s
    sell_levels <= 256'd0;                                         // sets the ouput to all 0s
    out_of_range <= 1'd0;                                          // sets the output to 0
    error <= 1'd0;                                                 // sets the output to 0
    for(i=0; i<256; i=i+1) begin                                   // makes the qty map all 0s to start with
        buy_qty_map[i] = 32'd0;
        sell_qty_map[i] = 32'd0;
    end
end

always@(posedge clk) begin
    error <= 1'd0;                                                 // resetting the error flag to 0 at the start of every clock cycle    
    out_of_range <= 1'd0;                                          // resetting the out of range flag to 0 at the start of every clock cycle
    if(change_valid) begin                                         // there is a new order to process
        
        if(change_price < BASE_PRICE || change_price > BASE_PRICE + LEVELS*TICK) begin     // if the price is out of the range of this module, set the out of range flag
            out_of_range <= 1'd1;                                  // flag set
        end
        else begin
            out_of_range <= 1'd0;                                  // if not clear flag
    
            case(change_side)                                      // is it a sell of buy order that we are add/removing
                1'd0: begin                                        // its a buy order
                    if(change_add) begin                           // are we ading or removing a buy order
                        buy_levels[index_price] <= 1'd1;           // set the level at this price to 1 indicating a buyer on that level
                        buy_qty_map[index_price] <= buy_qty_map[index_price] + change_qty;     // add the qty to the map for this price level
                    
                    end
                    else begin                                    
                        if(buy_qty_map[index_price] < change_qty) begin     // is there enough qty to remove from this level, if not set the error flag
                            error <= 1'd1;                                  //                                               ^^^^^^^^^^^^^^^^^^^^^^^^^^
                        end
                        else begin 
                            buy_qty_map[index_price] <= buy_qty_map[index_price] -change_qty;   // there is enough qty, so remove the right amount
                            if(buy_qty_map[index_price]-change_qty == 32'd0) begin              // if the qty at that level will become 0 then remove the buy flag at that price level
                                buy_levels[index_price] <= 1'd0;                                //                                             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                            end
                        end
                    end
                end
                1'd1: begin                                        // its a sell order
                    if(change_add) begin                           // are we removing or adding a sell order
                        sell_levels[index_price] <= 1'd1;          // we are adding a sell order so set the level to a high for sell
                        sell_qty_map[index_price] <= sell_qty_map[index_price] + change_qty;    // add the sell quanitity to that price level
                    
                    end
                    else begin
                        if(sell_qty_map[index_price] < change_qty) begin    // is there enough qty to remove from this level, if not set the error flag
                            error <= 1'd1;                                  //                                               ^^^^^^^^^^^^^^^^^^^^^^^^^^
                        end
                        else begin
                            sell_qty_map[index_price] <= sell_qty_map[index_price] - change_qty;        // there is enough quantity >>> remove the quantity
                            if(sell_qty_map[index_price]-change_qty == 32'd0) begin                     // if the quantity will become 0 then remove the sell flag
                                sell_levels[index_price] <= 1'd0;                                       //                                   ^^^^^^^^^^^^^^^^^^^^^
                            
                            end
                        end
                    end
                end
            endcase
        end
    
    end
end
endmodule