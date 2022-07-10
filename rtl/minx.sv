module minx
(
    input clk,
    input rt_clk,
    input reset,
    input [7:0] data_in,
    input [7:0] keys_active,
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
    // @todo: Design question: Move this logic to inside the eeprom module?
    // The idea of putting this logic here is that eeprom is part of the gpio
    // and gpio, as a module is not implemented (yet).
    reg [7:0] reg_io_dir;
    reg [7:0] reg_io_data;
    reg cpu_write_latch;
    wire eeprom_data_out;
    wire [7:0] eeprom_data = {4'h0, reg_io_data[3], (reg_io_dir[2]? reg_io_data[2]: eeprom_data_out), 2'd0};
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
                io_data_out = eeprom_data;
            default:
                io_data_out = 8'd0;
        endcase
    end

    wire [31:0]  irqs;
    assign irqs[5'h03] = irq_copy_complete;
    assign irqs[5'h04] = irq_render_done;
    assign irqs[5'h07] = t1_irqs[1];
    assign irqs[5'h08] = t1_irqs[0];
    assign irqs[5'h0B] = t256_irqs[0];
    assign irqs[5'h0C] = t256_irqs[1];
    assign irqs[5'h0C] = t256_irqs[2];
    assign irqs[5'h0E] = t256_irqs[3];

    wire [23:0] irq_address_out;
    wire [7:0]  irq_data_out;
    wire [3:0]  cpu_irq;
    irq irq
    (
        .clk             (clk),
        .reset           (reset),
        .bus_write       (write),
        .bus_read        (read),
        .irqs            (irqs),
        .cpu_iack        (iack),
        .bus_address_in  (cpu_address_out),
        .bus_data_in     (cpu_data_out),
        .bus_address_out (irq_address_out),
        .bus_data_out    (irq_data_out),
        .cpu_irq         (cpu_irq)
    );

    wire [7:0] key_data_out;
    key_input key_input
    (
        .reset          (reset),
        .keys_active    (keys_active),
        .bus_address_in (cpu_address_out),
        .bus_data_out   (key_data_out)
    );

    wire [7:0] sc_data_out;
    system_control system_control
    (
        .clk            (clk),
        .reset          (reset),
        .bus_write      (write),
        .bus_address_in (cpu_address_out),
        .bus_data_in    (cpu_data_out),
        .bus_data_out   (sc_data_out)
    );

    wire [7:0] sound_data_out;
    sound sound
    (
        .clk            (clk),
        .reset          (reset),
        .bus_write      (write),
        .bus_address_in (cpu_address_out),
        .bus_data_in    (cpu_data_out),
        .bus_data_out   (sound_data_out)
    );

    wire [2:0] t1_irqs;
    wire [7:0] timer1_data_out;
    wire osc256;
    timer timer1
    (
        .clk            (clk),
        .rt_clk         (rt_clk),
        .reset          (reset),
        .bus_write      (write),
        .bus_read       (read),
        .bus_address_in (cpu_address_out),
        .bus_data_in    (cpu_data_out),
        .bus_data_out   (timer1_data_out),
        .irqs           (t1_irqs),
        .osc256         (osc256)
    );

    wire [7:0] rtc_data_out;
    rtc rtc
    (
        .clk            (clk),
        .rt_clk         (rt_clk),
        .reset          (reset),
        .bus_write      (write),
        .bus_address_in (cpu_address_out),
        .bus_data_in    (cpu_data_out),
        .bus_data_out   (rtc_data_out)
    );

    wire [3:0] t256_irqs;
    wire [7:0] timer256_data_out;
    timer256 timer256
    (
        .clk            (clk),
        .rt_clk         (rt_clk),
        .reset          (reset),
        .bus_write      (write),
        .bus_read       (read),
        .bus_address_in (cpu_address_out),
        .bus_data_in    (cpu_data_out),
        .bus_data_out   (timer256_data_out),
        .irqs           (t256_irqs),
        .osc256         (osc256)
    );

    eeprom rom
    (
        .clk(clk),
        .reset(reset),
        .ce(reg_io_data[3] | ~reg_io_dir[3]),
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

    wire [7:0] sys_batt = (address_out == 24'h2010)? 8'h18: 0;
    wire [7:0] reg_data_out = 0
        | lcd_data_out
        | prc_data_out
        | key_data_out
        | io_data_out
        | sc_data_out
        | sound_data_out
        | rtc_data_out
        | timer256_data_out
        | timer1_data_out
        | irq_data_out
        | sys_batt;

    wire [7:0] cpu_data_in = 
    (
        (address_out >= 24'h2000) &&
        (address_out <  24'h2100) &&
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
        .data_in               ((cpu_bus_status == cpu.BUS_COMMAND_IRQ_READ)? irq_data_out: cpu_data_in),
        .irq                   (cpu_irq),
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
