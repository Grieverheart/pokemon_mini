// @todo: Implement interrupts

module timer
(
    input clk,
    input rt_clk,
    input reset,
    input bus_write,
    input bus_read,
    input [23:0] bus_address_in,
    input [7:0] bus_data_in,
    output logic [7:0] bus_data_out,
    output logic [3:0] irqs
);

reg reg_enabled;
reg reg_reset;
reg [7:0] timer;

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
    begin
        timer <= 8'd0;
        irqs  <= 4'd0;
    end
    else if(reg_enabled)
    begin
        timer <= timer + 8'd1;
        irqs  <= 4'd0;

        if(timer == 8'd255)
            irqs[3] <= 1;
        if(timer[6:0] == 7'd127)
            irqs[2] <= 1;
        if(timer[4:0] == 5'd31)
            irqs[1] <= 1;
        if(timer[2:0] == 3'd7)
            irqs[0] <= 1;
    end
end

endmodule
