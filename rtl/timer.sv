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
    output logic [1:0] irqs
);

reg [15:0] reg_control;
reg [15:0] reg_compare;
reg [15:0] reg_preset;
reg [7:0]  reg_scale;
reg [7:0]  reg_osc_control;
reg [15:0] timer;

wire reset_l   = reg_control[1];
wire enabled_l = reg_control[2];
wire mode16    = reg_control[7];
wire reset_h   = reg_control[9];
wire enabled_h = reg_control[10];

wire osc1_enabled = reg_osc_control[5];
wire osc2_enabled = reg_osc_control[4];

wire osc_l = reg_osc_control[0];
wire osc_h = reg_osc_control[1];

reg write_latch;
always_ff @ (negedge clk)
begin
    if(reset)
    begin
        reg_control <= 16'd0;
    end
    else
    begin
        if(write_latch)
        begin
            case(bus_address_in)
                24'h2018:
                    reg_scale         <= bus_data_in;
                24'h2019:
                    reg_osc_control   <= bus_data_in;
                24'h2030:
                    reg_control[7:0]  <= bus_data_in;
                24'h2031:
                    reg_control[15:8] <= bus_data_in;
                24'h2032:
                    reg_preset[7:0]   <= bus_data_in;
                24'h2033:
                    reg_preset[15:8]  <= bus_data_in;
                24'h2034:
                    reg_compare[7:0]  <= bus_data_in;
                24'h2035:
                    reg_compare[15:8] <= bus_data_in;
                default:
                begin
                end
            endcase
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
        24'h2018:
            bus_data_out = reg_scale;
        24'h2019:
            bus_data_out = reg_osc_control;
        24'h2030:
            bus_data_out = reg_control[7:0];
        24'h2031:
            bus_data_out = reg_control[15:8];
        24'h2032:
            bus_data_out = reg_preset[7:0];
        24'h2033:
            bus_data_out = reg_preset[15:8];
        24'h2034:
            bus_data_out = reg_compare[7:0];
        24'h2035:
            bus_data_out = reg_compare[15:8];
        24'h2036:
            bus_data_out = timer[7:0];
        24'h2037:
            bus_data_out = timer[15:8];
        default:
            bus_data_out = 8'd0;
    endcase
end

reg rt_clk_latch;
wire rt_clk_edge = (rt_clk & ~rt_clk_latch);
always_ff @ (posedge clk)
begin
    rt_clk_latch <= rt_clk;

    if(mode16)
    begin
        if(enabled_l)
        begin
            if(~osc_l || rt_clk_edge)
            begin
                if(timer == 0)
                    timer <= reg_preset;
                else
                    timer <= timer - 1;
            end
        end
    end
    else
    begin
        if(enabled_l)
        begin
            if(~osc_l || rt_clk_edge)
            begin
                if(timer == 0)
                    timer[7:0] <= reg_preset[7:0];
                else
                    timer[7:0] <= timer[7:0] - 1;
            end
        end

        if(enabled_h)
        begin
            if(~osc_h || rt_clk_edge)
            begin
                if(timer == 0)
                    timer[15:8] <= reg_preset[15:8];
                else
                    timer[15:8] <= timer[15:8] - 1;
            end
        end
    end
end

endmodule
