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

    input irq_copy_complete,
    input irq_render_done,
    input irq_32Hz,
    input irq_8Hz,
    input irq_2Hz,
    input irq_1Hz
);

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
