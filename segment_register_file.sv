module segment_register_file
(
    input clk,
    input reset,
    input we,
    input [1:0] write_id,
    input [15:0] write_data,

    output reg [15:0] registers[0:3]
);

    always @(posedge clk)
    begin
        if(reset)
        begin
            for(int i = 0; i < 4; ++i)
                registers[i] <= 16'd0;
            registers[1] <= 16'hFFFF;
        end
        else
        begin
            if(we)
            begin
                registers[write_id] <= write_data;
            end
        end
    end
endmodule;
