// @todo: Implement interrupts

module timer256
(
    input clk,
    input rt_clk,
    input reset,
    input bus_write,
    input bus_read,
    input [23:0] bus_address_in,
    input [7:0] bus_data_in,
    output logic [7:0] bus_data_out,
    output logic [7:0] timer
    //output reg [3:0] irqs
);

reg reg_enabled;
reg reg_reset;

//assign irqs = {4{reg_enabled}} & {timer == 0, timer[7], timer[5], timer[3]};

reg write_latch;
always_ff @ (negedge clk)
begin
    if(reset)
    begin
        reg_enabled <= 1'd0;
        reg_reset   <= 1'd0;
    end
    else
    begin
        if(reg_reset && timer == 0)
            reg_reset <= 0;

        if(write_latch)
        begin
            if(bus_address_in == 24'h2040)
            begin
                reg_enabled <= bus_data_in[0];
                reg_reset   <= bus_data_in[1];
            end
        end
    end
end

always_ff @ (posedge clk)
begin
    write_latch <= 0;
    if(bus_write) write_latch <= 1;
end

always_comb
begin
    case(bus_address_in)
        24'h2040:
            bus_data_out = {7'd0, reg_enabled};
        24'h2041:
            bus_data_out = timer;
        default:
            bus_data_out = 8'd0;
    endcase
end

always_ff @ (posedge rt_clk)
begin
    if(reset || reg_reset)
        timer <= 8'd0;
    else if(reg_enabled)
    begin
        timer <= timer + 8'd1;
        //if(timer == 8'd255)
        //    irqs[] <= 1;
    end
end

endmodule
