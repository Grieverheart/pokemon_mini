module register_file
#(
    parameter NUM_REGISTERS=8
)
(
    input clk,
    input reset,

    input we,
    input [$clog2(NUM_REGISTERS)-1:0] write_id,
    input [15:0] write_data,

    input we_secondary,
    input [$clog2(NUM_REGISTERS)-1:0] write_id_secondary,
    input [15:0] write_data_secondary,

    output reg [15:0] registers[0:NUM_REGISTERS-1]
);

    always @(posedge clk)
    begin
        if(reset)
        begin
            for(int i = 0; i < NUM_REGISTERS; ++i)
                registers[i] <= 16'd0;
        end
        else
        begin
            if(we_secondary)
                registers[write_id_secondary] <= write_data_secondary;

            if(we)
                registers[write_id] <= write_data;
        end
    end
endmodule;
