// @todo: Implement interrupts

module irq
(
    input clk,
    input reset,
    input bus_write,
    input bus_read,
    input [4:0] irqs,
    input [1:0] cpu_i01,
    input [23:0] bus_address_in,
    input [7:0] bus_data_in,
    output logic [23:0] bus_address_out,
    output logic [7:0] bus_data_out,
    output logic [3:0] cpu_irq,
);

reg [3:0] irq_group[0:31] = '{
    0, 0, 0,                // NMI
    3, 3,                   // Blitter Group
    2, 2,                   // Tim3/2
    1, 1,                   // Tim1/0
    0, 0,                   // Tim5/4
    7, 7, 7, 7,             // 256hz clock
    8, 8, 8, 8,             // IR / Shock sensor
    6, 6,                   // K1x
    5, 5, 5, 5, 5, 5, 5, 5, // K0x
    4, 4, 4                 // Unknown ($1D ~ $1F?)
};

// $03     $04     $05     $06     $07     $08     $09     $0A
//                 $0B     $0C     $0D     $0E     $13     $14
// $15     $16     $17     $18     $19     $1A     $1B     $1C
// $0F     $10     ???     ???             $1D     $1E     $1F
reg [4:0] irq_reg_map[0:31] = '{
    8, 9, 28, 0, 1, 2, 3, 4, 5, 6, 7,
    10, 11, 12, 13, 24, 25, 26, 27, 14, 15
    16, 17, 18, 19, 20, 21, 22, 23, 29, 30, 31
};

reg [17:0] reg_irq_priority;
reg [31:0] reg_irq_active;
reg [31:0] reg_irq_enabled;

reg [4:0] next_irq;
reg [4:0] next_priority;

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
            if(cpu_address_out == 24'h2020)
                reg_irq_priority[7:0] <= cpu_data_out;

            if(cpu_address_out == 24'h2021)
                reg_irq_priority[15:8] <= cpu_data_out;

            if(cpu_address_out == 24'h2022)
                reg_irq_priority[17:16] <= cpu_data_out[1:0];

            if(cpu_address_out == 24'h2023)
                reg_irq_enabled[7:0] <= cpu_data_out;

            if(cpu_address_out == 24'h2024)
                reg_irq_enabled[15:8] <= cpu_data_out;

            if(cpu_address_out == 24'h2025)
                reg_irq_enabled[23:16] <= cpu_data_out;

            if(cpu_address_out == 24'h2026)
                reg_irq_enabled[31:24] <= cpu_data_out;

            if(cpu_address_out == 24'h2027)
                reg_irq_active[7:0] <= cpu_data_out;

            if(cpu_address_out == 24'h2028)
                reg_irq_active[15:8] <= cpu_data_out;

            if(cpu_address_out == 24'h2029)
                reg_irq_active[23:16] <= cpu_data_out;

            if(cpu_address_out == 24'h202A)
                reg_irq_active[31:24] <= cpu_data_out;
        end
    end
end

always_ff @ (posedge clk)
begin
    write_latch <= 0;
    if(bus_write) write_latch <= 1;

    for(i = 0; i < 32; ++i)
    begin
        if(irqs[i] && reg_irq_active[irq_reg_map[i]] && reg_irq_priority[irq_group[i]] > next_priority)
        begin
            next_irq      <= i;
            next_priority <= reg_irq_priority[irq_group[i]];
        end

        if(next_priority > cpu_i01)
        begin
            cpu_irq[next_priority-1] <= 1;
            bus_address_out          <= {19'd0, next_irq};
        end
    end
end


always_comb
begin
    case(bus_address_in)
        24'h2020:
            bus_data_out = reg_irq_priority[7:0];

        24'h2021:
            bus_data_out = reg_irq_priority[15:8];

        24'h2022:
            bus_data_out = {6'd0, reg_irq_priority[17:16]};

        24'h2023:
            bus_data_out = reg_irq_enabled[7:0];

        24'h2024:
            bus_data_out = reg_irq_enabled[15:8];

        24'h2025:
            bus_data_out = reg_irq_enabled[23:16];

        24'h2026:
            bus_data_out = reg_irq_enabled[31:24];

        24'h2027:
            bus_data_out = reg_irq_active[7:0];

        24'h2028:
            bus_data_out = reg_irq_active[15:8];

        24'h2029:
            bus_data_out = reg_irq_active[23:16];

        24'h202A:
            bus_data_out = reg_irq_active[31:24];

        default:
        begin
        end
    endcase
end

endmodule
