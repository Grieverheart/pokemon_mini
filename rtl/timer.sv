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
wire [2:0] prescale_l = reg_scale[2:0];
wire [2:0] prescale_h = reg_scale[6:4];

wire osc1_enabled = reg_osc_control[5];
wire osc2_enabled = reg_osc_control[4];

wire osc_l = reg_osc_control[0];
wire osc_h = reg_osc_control[1];

//localparam [3:0] prescale_osc1[0:7] = '{
//    1, 3, 5, 6, 7, 8, 10, 12
//};
//
//localparam [2:0] prescale_osc2[0:7] = '{
//    0, 1, 2, 3, 4, 5, 6, 7
//};

function tick(input osc, input [2:0] pid);
    if(osc == 0)
    begin
        case(pid)
            3'd0:
                tick = osc1prescaler[0] == 1'h1;
            3'd1:
                tick = osc1prescaler[2:0] == 3'h7;
            3'd2:
                tick = osc1prescaler[4:0] == 5'h1F;
            3'd3:
                tick = osc1prescaler[5:0] == 6'h3F;
            3'd4:
                tick = osc1prescaler[6:0] == 7'h7F;
            3'd5:
                tick = osc1prescaler[7:0] == 8'hFF;
            3'd6:
                tick = osc1prescaler[9:0] == 10'h3FF;
            3'd7:
                tick = osc1prescaler[11:0] == 12'hFFF;
        endcase
    end
    else
    begin
        case(pid)
            3'd0:
                tick = 1;
            3'd1:
                tick = osc2prescaler[0] == 1'h1;
            3'd2:
                tick = osc2prescaler[1:0] == 2'h3;
            3'd3:
                tick = osc2prescaler[2:0] == 3'h7;
            3'd4:
                tick = osc2prescaler[3:0] == 4'hF;
            3'd5:
                tick = osc2prescaler[4:0] == 5'h1F;
            3'd6:
                tick = osc2prescaler[5:0] == 6'h3F;
            3'd7:
                tick = osc2prescaler[6:0] == 7'h7F;
        endcase
    end
endfunction

reg write_latch;
always_ff @ (negedge clk)
begin
    if(reset)
    begin
        reg_control <= 16'd0;
    end
    else
    begin
        if(reset_l)
            reg_control[1] <= 0;

        if(reset_h)
            reg_control[9] <= 0;

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
reg [11:0] osc1prescaler;
always_ff @ (posedge clk)
begin
    osc1prescaler   <= osc1prescaler + 1;
    rt_clk_latch <= rt_clk;

    if(reset_l)
        timer <= reg_preset;

    if(mode16)
    begin
        if(enabled_l)
        begin
            //if(osc1prescaler == 2**prescale_osc1[prescale_l] - 1)
            //begin
            //    osc1prescaler <= 0;
            if(tick(osc_l, prescale_l))
            begin
                if(~osc_l || rt_clk_edge)
                begin
                    if(timer == 0)
                    begin
                        // Fire IRQ
                        timer <= reg_preset;
                    end
                    else
                        timer <= timer - 1;

                    if(timer <= reg_compare)
                    begin
                        // Fire IRQ
                    end
                end
            end
        end
    end
    else
    begin
        if(reset_h)
            timer[15:8] <= reg_preset[15:8];

        if(enabled_l)
        begin
            if(tick(osc_l, prescale_l))
            begin
                if(~osc_l || rt_clk_edge)
                begin
                    if(timer == 0)
                    begin
                        // Fire IRQ
                        timer[7:0] <= reg_preset[7:0];
                    end
                    else
                        timer[7:0] <= timer[7:0] - 1;

                    if(timer[7:0] <= reg_compare[7:0])
                    begin
                        // Fire IRQ
                    end
                end
            end
        end

        if(enabled_h)
        begin
            if(tick(osc_h, prescale_h))
            begin
                if(~osc_h || rt_clk_edge)
                begin
                    if(timer == 0)
                    begin
                        // Fire IRQ
                        timer[15:8] <= reg_preset[15:8];
                    end
                    else
                        timer[15:8] <= timer[15:8] - 1;
                end
            end
        end
    end
end

reg [6:0] osc2prescaler;
always_ff @ (posedge rt_clk)
begin
    osc2prescaler <= osc2prescaler + 1;
end

endmodule
