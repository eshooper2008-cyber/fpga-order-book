module parse(
    input clk,
    input valid,
    input [7:0] data,
    output reg msg_valid,
    output reg [31:0] price,
    output reg [7:0] type,
    output reg [31:0] ID,
    output reg [7:0] side,
    output reg [31:0] qty,
    output reg [31:0] new_ID

);

reg [4:0] index = 5'd0;


always @(posedge clk) begin
    msg_valid <= 1'd0;
    if(valid) begin       
        case(index)
            5'd0: begin 
                type <= data;
            end 
            5'd1: begin 
                ID <= {ID[23:0], data};
            end
            5'd2: begin 
                ID <= {ID[23:0], data};
            end
            5'd3: begin 
                ID <= {ID[23:0], data};
            end
            5'd4: begin 
                ID <= {ID[23:0], data};
            end
            5'd5: begin 
                side<= data;
            end
            5'd6: begin 
                qty <= {qty[23:0], data};
            end
            5'd7: begin 
                qty <= {qty[23:0], data};
            end
            5'd8: begin 
                qty <= {qty[23:0], data};
            end
            5'd9: begin 
                qty <= {qty[23:0], data};
            end
            5'd10: begin 
                price <= {price[23:0], data};
            end
            5'd11: begin 
                price <= {price[23:0], data};
            end
            5'd12: begin 
                price <= {price[23:0], data};
            end
            5'd13: begin 
                price <= {price[23:0], data};
            end
            5'd14: begin 
                new_ID <= {new_ID[23:0],data};
            end
            5'd15: begin 
                new_ID <= {new_ID[23:0],data};
            end
            5'd16: begin 
                new_ID <= {new_ID[23:0],data};
            end
            5'd17: begin 
                new_ID <= {new_ID[23:0],data};
            end
        endcase
        
        if(index == 5'd17) begin
            index <= 5'd0;
            msg_valid <= 1'b1;
        end
        else begin
            index <= index +5'd1;
        end
    end
end 



endmodule
