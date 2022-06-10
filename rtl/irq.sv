// @todo: Implement interrupts

module irq
(
    input clk,
    input reset,
    input bus_write,
    input bus_read,
    input [23:0] bus_address_in,
    input [7:0] bus_data_in,
    output logic [7:0] bus_data_out,

    input [4:0] irqs,
);

reg [3:0] irq_group[0:31] = '{
    0, 0, 0,                // NMI
    0, 0,                   // Blitter Group
    1, 1,                   // Tim3/2
    2, 2,                   // Tim1/0
    3, 3,                   // Tim5/4
    4, 4, 4, 4,             // 256hz clock
    8, 8, 8, 8,             // IR / Shock sensor
    5, 5,                   // K1x
    6, 6, 6, 6, 6, 6, 6, 6, // K0x
    7, 7, 7                 // Unknown ($1D ~ $1F?)
};

reg [31:0] reg_irq_priority;
reg [31:0] reg_irq_active;

reg write_latch;
always_ff @ (negedge clk)
begin
    if(reset)
    begin
    end
    else
    begin
        if(write_latch)
        begin
        end
    end
end

always_ff @ (posedge clk)
begin
    write_latch <= 0;
    if(bus_write) write_latch <= 1;

    for(i = 0; i < 32; ++i)
    begin
        if(irqs[i] && reg_irq_active[i] && reg_irq_priority[irq_group[i]] > next_priority)
        begin
            next_irq <= i;
            next_priority <= reg_irq_priority[irq_group[i]];
        end
    end
end


//always_comb
//begin
//    case(bus_address_in)
//        24'h2040:
//            bus_data_out = {7'd0, reg_enabled};
//        24'h2041:
//            bus_data_out = timer;
//        default:
//            bus_data_out = 8'd0;
//    endcase
//end

endmodule
