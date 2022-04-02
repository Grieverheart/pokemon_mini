module minx
(
    input clk,
    input reset,
    input [7:0] data_in,
    input [3:0] irq,
    output logic pk,
    output logic pl,
    output wire [1:0] i01,

    output logic [7:0] data_out,
    output logic [23:0] address_out,
    output logic [1:0]  bus_status,
    output logic read,
    output logic read_interrupt_vector,
    output wire write,
    output wire sync,
    output logic iack
);

    assign data_out = cpu_data_out;

    wire [7:0] lcd_data_out;
    lcd_controller lcd
    (
        .clk(clk),
        .reset(reset),
        .pk(pk),
        .pl(pl),
        .cpu_write(write),
        .cpu_read(read),
        .address_in(address_out),
        .data_in(cpu_data_out),
        .data_out(lcd_data_out)
    );

    wire [7:0] cpu_data_out;
    wire [7:0] cpu_data_in = (
        (address_out == 24'h20FE || address_out == 24'h20FF) &&
        (bus_status == cpu.BUS_COMMAND_MEM_READ)
    )? lcd_data_out: data_in;

    //wire [7:0] reg_data_out = lcd_data_out; // More to come.
    //wire [7:0] cpu_data_in = (
    //    (address_out >= 24'h2000 && address_out < 24'h2100) &&
    //    (bus_status == cpu.BUS_COMMAND_MEM_READ)
    //)? reg_data_out: data_in;

    s1c88 cpu
    (
        .clk                   (clk),
        .reset                 (reset),
        .data_in               (cpu_data_in),
        .irq                   (irq),
        .pk                    (pk),
        .pl                    (pl),
        .i01                   (i01),
        .data_out              (cpu_data_out),
        .address_out           (address_out),
        .bus_status            (bus_status),
        .read                  (read),
        .read_interrupt_vector (read_interrupt_vector),
        .write                 (write),
        .sync                  (sync),
        .iack                  (iack)
    );

endmodule
