
module s1c88
(
    input clk,
    input reset,
    input [7:0] data_in,
    output [7:0] data_out,

    output logic [23:0] address_out,
    output logic [1:0]  bus_status,
    output logic read,
    output logic write
);

    // @todo:
    // * Implement decoder?

    enum [1:0]
    {
        BUS_COMMAND_IDLE      = 2'd0,
        BUS_COMMAND_IRQ_READ  = 2'd1,
        BUS_COMMAND_MEM_WRITE = 2'd2,
        BUS_COMMAND_MEM_READ  = 2'd3
    } BusCommand;

    localparam [2:0]
        STATE_IDLE          = 3'd0,
        STATE_OPCODE_READ   = 3'd1,
        STATE_OPEXT_READ    = 3'd2,
        STATE_IMM_LOW_READ  = 3'd3,
        STATE_IMM_HIGH_READ = 3'd4,
        STATE_EXECUTE       = 3'd5;

    reg [2:0] state = STATE_IDLE;

    reg imm_size = 0;
    reg need_opext = 0;
    reg need_imm = 0;

    wire [2:0] next_state =
        (state == STATE_IDLE) ?
            STATE_OPCODE_READ:

        (state == STATE_OPCODE_READ) ?
            (need_opext  ? STATE_OPEXT_READ:
            (need_imm    ? STATE_IMM_LOW_READ:
                           STATE_EXECUTE)):

        (state == STATE_OPEXT_READ) ?
            (need_imm    ? STATE_IMM_LOW_READ:
                           STATE_EXECUTE):

        (state == STATE_IMM_LOW_READ) ?
            (imm_size    ? STATE_IMM_HIGH_READ:
                           STATE_EXECUTE):

        (state == STATE_IMM_HIGH_READ) ?
                           STATE_EXECUTE:
                           STATE_OPCODE_READ;

    reg [15:0] PC;

    reg [7:0] opcode;
    reg [7:0] opext;
    reg [7:0] imm_low;
    reg [7:0] imm_high;

    reg [1:0] reset_counter;

    decode decode_inst
    (
        .opcode,
        .opext,

        .need_opext,

        .need_imm,
        .imm_size

        //.src(src_operand),
        //.dst(dst_operand),

        //.byte_word_field(byte_word_field)
    );

    always_ff @ (negedge clk)
    begin
        if(reset)
        begin
            address_out <= ~0;
            bus_status <= BUS_COMMAND_IDLE;
        end
        else if(reset_counter >= 2)
        begin
            address_out <= {9'b0, PC[14:0]};
            bus_status <= (next_state != STATE_EXECUTE)? BUS_COMMAND_MEM_READ: BUS_COMMAND_MEM_WRITE;
        end
    end

    always_ff @ (posedge clk)
    begin
        if(reset)
        begin
            state <= STATE_IDLE;
            read  <= 0;
            write <= 0;
            reset_counter <= 0;
        end
        else if(reset_counter < 2)
        begin
            reset_counter <= reset_counter + 1;
        end
        else
        begin
            state <= next_state;
            case(state)
                STATE_IDLE:
                begin
                    read <= 1;
                end

                STATE_OPCODE_READ:
                begin
                    opcode <= data_in;
                    read   <= (next_state == STATE_EXECUTE)? 0: 1;
                    PC <= PC + 1;
                end

                STATE_OPEXT_READ:
                begin
                    opext <= data_in;
                    read  <= (next_state == STATE_EXECUTE)? 0: 1;
                    PC <= PC + 1;
                end

                STATE_IMM_LOW_READ:
                begin
                    imm_low <= data_in;
                    read    <= (next_state == STATE_EXECUTE)? 0: 1;
                    PC <= PC + 1;
                end

                STATE_IMM_HIGH_READ:
                begin
                    imm_high <= data_in;
                    read     <= 0;
                    PC <= PC + 1;
                end

                STATE_EXECUTE:
                begin
                    read <= 1;
                end

                default:
                begin
                end
            endcase
        end
    end

endmodule;

