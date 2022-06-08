// Basically timer + register logic + overflow logic? How much should we
// implement in the module? Alternatively, we could make this just a simple
// timer and put the rest of the logic in minx.sv.

module timer256
(
    input clk,
    input rt_clk,
    input reset,
    input bus_write,
    input bus_read,
    input [23:0] bus_address_in,
    input [7:0] bus_data_in,
    output logic [7:0] timer
);

always_ff @ (posedge rt_clk)
begin
    if(reset)
        timer <= 8'd0;
    else
        timer <= timer + 8'd1;
end

endmodule
