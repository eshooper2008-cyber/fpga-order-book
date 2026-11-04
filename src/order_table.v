module order_table(
    input clk, 
    input valid,
    input [7:0] msg_type,
    input [31:0] ID,
    input [7:0] side,              // h53 for 1, h42 for 0
    input [31:0] qty,
    input [31:0] price,
    input [31:0] new_ID,
    output reg change_valid,
    output reg change_side,         // 0 for buy, 1 for sell
    output reg [31:0] change_price,
    output reg [31:0] change_qty,
    output reg change_add,
    output reg not_found

);



reg [71:0] mem [0:255];               // 72 bits per entry, 256 entries (ID tells you want address the info for that order is in)      
reg pending_add = 1'd0;
reg [71:0] pending_data = 72'd0;

integer i;

initial for(i=0; i<256; i= i+1) begin 
    mem[i] <= 72'd0;
end


always @(posedge clk) begin 
    not_found <= 1'd0;
    change_valid <= 1'd0;
    if(pending_add) begin
        change_valid <= 1'd1;
        change_side <= pending_data[71:64] == 8'h42 ? 1'd0 : 1'd1;
        change_price <= pending_data[63:32];
        change_qty <= pending_data[31:0];
        change_add <= 1'd1;
        pending_add <= 1'd0;
    end
    if(valid) begin 
        case(msg_type)  
            8'h41: begin // Add order
                mem[ID[7:0]] <= {side,price,qty};
                change_valid <= 1'd1;
                change_side <= (side == 8'h42) ? 1'd0 : 1'd1;
                change_price <= price;
                change_qty <= qty;
                change_add <= 1'd1;
                not_found <= 1'd0;
            end
            8'h45: begin // Execute order
                if(mem[ID[7:0]] == 72'd0) begin
                    not_found <= 1'd1;
                    change_valid <= 1'd0;
                end 
                else begin 
                    mem[ID[7:0]] <= {mem[ID[7:0]][71:64], mem[ID[7:0]][63:32], mem[ID[7:0]][31:0] - qty};
                    change_valid <= 1'd1;
                    change_side <= (mem[ID[7:0]][71:64] == 8'h42) ? 1'd0 : 1'd1;
                    change_price <= mem[ID[7:0]][63:32];
                    change_qty <= qty;
                    change_add <= 1'd0;
                    not_found <= 1'd0;
                end
                if(mem[ID[7:0]][31:0] == qty) begin
                    mem[ID[7:0]] <= 72'd0;
                end
            end
            8'h58: begin   // Cancel order
                if(mem[ID[7:0]] == 72'd0) begin
                    not_found <= 1'd1;
                    change_valid <= 1'd0;
                end
                else begin
                    mem[ID[7:0]] <= {mem[ID[7:0]][71:64], mem[ID[7:0]][63:32], mem[ID[7:0]][31:0] - qty};
                    change_valid <= 1'd1;
                    change_side <= (mem[ID[7:0]][71:64] == 8'h42) ? 1'd0 : 1'd1;
                    change_price <= mem[ID[7:0]][63:32];
                    change_qty <= qty;
                    change_add <= 1'd0;
                    not_found <= 1'd0;
                end
                if(mem[ID[7:0]][31:0] == qty) begin
                    mem[ID[7:0]] <= 72'd0;
                end
            end
            8'h44: begin    // Delete order
                if(mem[ID[7:0]] == 72'd0) begin
                    not_found <= 1'd1;
                    change_valid <= 1'd0;
                end
                else begin
                    mem[ID[7:0]] <= 72'd0;
                    change_valid <= 1'd1;
                    change_side <= (mem[ID[7:0]][71:64] == 8'h42) ? 1'd0 : 1'd1;
                    change_price <= mem[ID[7:0]][63:32];
                    change_qty <= mem[ID[7:0]][31:0];
                    change_add <= 1'd0;
                    not_found <= 1'd0;
                end
            end
            8'h55: begin    // Replace order
                if(mem[ID[7:0]] == 72'd0) begin
                    not_found <= 1'd1;
                    change_valid <= 1'd0;
                end
                else begin
                    mem[ID[7:0]] <= 72'd0;
                    mem[new_ID[7:0]] <= {mem[ID[7:0]][71:64], price, qty};
                    change_valid <= 1'd1;
                    change_side <= {mem[ID[7:0]][71:64] == 8'h42} ? 1'd0 : 1'd1;
                    change_price <= {mem[ID[7:0]][63:32]};
                    change_qty <= {mem[ID[7:0]][31:0]};
                    change_add <= 1'd0;
                    not_found <= 1'd0;
                    pending_data <= {mem[ID[7:0]][71:64], price, qty};
                    pending_add <= 1'd1;
                end
            end
        endcase
        end
    end
                    


                
endmodule