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
    reg [7:0] reg_io_dir;
    reg [7:0] reg_io_data;
    reg cpu_write_latch;
    wire eeprom_data_out; //@todo
    always_ff @ (negedge clk)
    begin
        if(cpu_write_latch)
        begin
            if(cpu_address_out == 24'h2060)
                reg_io_dir <= cpu_data_out;

            if(cpu_address_out == 24'h2061)
                reg_io_data <= cpu_data_out;
        end
    end

    always_ff @ (posedge clk)
    begin
        cpu_write_latch <= 0;
        if(cpu_write) cpu_write_latch <= 1;
    end

    reg [7:0] io_data_out;
    always_comb
    begin
        case(cpu_address_out)
            24'h2060:
                io_data_out = reg_io_dir;
            24'h2061:
                io_data_out = {4'd0, reg_io_data[3], (reg_io_dir[2]? eeprom_data_out: reg_io_data[2]), 2'd0};
            default:
                io_data_out = 8'd0;
        endcase
    end

    eeprom rom
    (
        .clk(clk),
        .reset(reset),
        .ce(reg_io_data[3]),
        .data_in(reg_io_data[2] | ~reg_io_dir[2]),
        .data_out(eeprom_data_out)
    );

    assign data_out    = bus_ack? prc_data_out    : cpu_data_out;
    assign address_out = bus_ack? prc_address_out : cpu_address_out;
    assign write       = bus_ack? prc_write       : cpu_write;
    assign read        = bus_ack? prc_read        : cpu_read;
    assign bus_status  = bus_ack? prc_bus_status  : cpu_bus_status;

    wire [7:0] lcd_data_out;
    lcd_controller lcd
    (
        .clk(clk),
        .reset(reset),
        .bus_write(write),
        .bus_read(read),
        .address_in(address_out),
        .data_in(data_out),
        .data_out(lcd_data_out)
    );

    wire bus_request;
    wire bus_ack;

    wire [7:0] prc_data_out;
    wire [23:0] prc_address_out;
    wire [7:0] prc_data_in = bus_ack? data_in: cpu_data_out;
    wire prc_write;
    wire prc_read;
    wire irq_copy_complete;
    wire irq_render_done;
    wire [1:0] prc_bus_status;
    prc prc
    (
        .clk               (clk),
        .reset             (reset),
        .bus_write         (write),
        .bus_read          (read),
        .bus_address_in    (address_out),
        .bus_data_in       (prc_data_in),
        .bus_data_out      (prc_data_out),
        .bus_address_out   (prc_address_out),
        .bus_status        (prc_bus_status),
        .write             (prc_write),
        .read              (prc_read),
        .bus_request       (bus_request),
        .bus_ack           (bus_ack),
        .irq_copy_complete (irq_copy_complete),
        .irq_render_done   (irq_render_done)
    );

    wire [7:0] reg_data_out = lcd_data_out | prc_data_out | io_data_out; // More to come.
    wire [7:0] cpu_data_in = (
            (address_out == 24'h20FE || address_out == 24'h20FF ||
            (address_out >= 24'h2080 && address_out <= 24'h8F)
        ) &&
        (bus_status == cpu.BUS_COMMAND_MEM_READ)
    )? reg_data_out: data_in;

    wire [7:0] cpu_data_out;
    wire [23:0] cpu_address_out;
    wire cpu_write;
    wire cpu_read;
    wire [1:0] cpu_bus_status;
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
        .address_out           (cpu_address_out),
        .bus_status            (cpu_bus_status),
        .read                  (cpu_read),
        .read_interrupt_vector (read_interrupt_vector),
        .write                 (cpu_write),
        .sync                  (sync),
        .iack                  (iack),
        .bus_request           (bus_request),
        .bus_ack               (bus_ack)
    );

endmodule
