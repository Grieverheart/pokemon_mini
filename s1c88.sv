
module s1c88
(
    input clk,
    input reset,
    input [7:0] data_in,
    output logic pk,
    output logic pl,

    output logic [7:0] data_out,
    output logic [23:0] address_out,
    output logic [1:0]  bus_status,
    output logic read,
    output logic write,
    output logic sync,
    output logic iack
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
        STATE_EXECUTE       = 3'd5,
        STATE_EXC_PROCESS   = 3'd6;

    localparam [2:0]
        EXCEPTION_TYPE_RESET   = 3'd0,
        EXCEPTION_TYPE_DIVZERO = 3'd1,
        EXCEPTION_TYPE_NMI     = 3'd2,
        EXCEPTION_TYPE_IRQ3    = 3'd3,
        EXCEPTION_TYPE_IRQ2    = 3'd4,
        EXCEPTION_TYPE_IRQ1    = 3'd5,
        EXCEPTION_TYPE_NONE    = 3'd6;

    reg [2:0] state = STATE_IDLE;

    reg imm_size = 0;
    reg need_opext = 0;
    reg need_imm = 0;

    wire [2:0] next_state =
        (state == STATE_IDLE || state == STATE_EXC_PROCESS) ?
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

    reg [15:0] PC = 16'hFACE;

    reg [7:0] opcode;
    reg [7:0] opext;
    reg [7:0] imm_low;
    reg [7:0] imm_high;

    reg [1:0] reset_counter;
    reg [2:0] exception = EXCEPTION_TYPE_NONE;

    reg [2:0] exception_process_step;

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

    always_ff @ (negedge clk, posedge reset)
    begin
        if(reset)
        begin
            sync          <= 0;
            iack          <= 0;
            address_out   <= ~0;
            data_out      <= ~0;
            write         <= 0;
            pl            <= 0;
            bus_status    <= BUS_COMMAND_IDLE;
            reset_counter <= 0;
            exception     <= EXCEPTION_TYPE_RESET;
        end
        else if(reset_counter < 2)
        begin
            reset_counter <= reset_counter + 1;
            if(reset_counter == 1)
            begin
                // Output dummy address
                address_out <= 24'hDEFACE;
            end
        end
        else
        begin
            pl <= ~pl;

            if(pl == 1)
            begin
                address_out <= {9'b0, PC[14:0]};
                sync <= 0;

                if(state == STATE_OPCODE_READ)
                begin
                    if(exception != EXCEPTION_TYPE_NONE)
                    begin
                        iack <= 1;
                        address_out <= 24'hDEFACE;
                    end
                    sync <= 1;
                end
                else if(state == STATE_EXC_PROCESS)
                begin
                    if(exception_process_step < 2)
                    begin
                        address_out <= 24'hDEFACE;
                    end
                    else if(exception_process_step == 2)
                    begin
                        address_out <= 0;
                    end
                    else if(exception_process_step == 3)
                    begin
                        address_out <= 1;
                        iack        <= 0;
                        exception   <= EXCEPTION_TYPE_NONE;
                    end
                end

                bus_status <= (state != STATE_EXECUTE)? BUS_COMMAND_MEM_READ: BUS_COMMAND_MEM_WRITE;
            end
        end
    end

    always_ff @ (posedge clk, posedge reset)
    begin
        if(reset)
        begin
            state         <= STATE_IDLE;
            read          <= 0;
            pk            <= 0;
        end
        else if(reset_counter >= 2)
        begin
            pk <= ~pk;
            read <= 0;

            // @note: When do we actually move to the next state?
            // For read states we probably want to move once every
            // bus cycle, but that's probably not required for the
            // execute phase.
            if(pk == 1)
                state <= next_state;

            case(state)
                STATE_IDLE:
                begin
                end

                STATE_EXC_PROCESS:
                begin
                    if(pk == 0)
                    begin
                        if(exception_process_step <= 3)
                        begin
                            read <= 1;
                        end
                    end
                    else
                    begin
                        exception_process_step <= exception_process_step + 1;
                        state <= STATE_EXC_PROCESS;
                        if(exception_process_step == 2)
                        begin
                            PC[7:0] <= data_in;
                        end
                        else if(exception_process_step == 3)
                        begin
                            PC[15:8] <= data_in;
                            state <= STATE_OPCODE_READ;
                        end
                    end
                end

                STATE_OPCODE_READ:
                begin
                    if(pk == 0)
                    begin
                        read <= 1;
                        PC <= PC + 1;

                        if(exception == EXCEPTION_TYPE_RESET)
                        begin
                            state <= STATE_EXC_PROCESS;
                            exception_process_step <= 0;
                        end
                    end
                    else
                        opcode <= data_in;
                end

                STATE_OPEXT_READ:
                begin
                    if(pk == 0)
                    begin
                        read  <= 1;
                        PC <= PC + 1;
                    end
                    else
                        opext <= data_in;
                end

                STATE_IMM_LOW_READ:
                begin
                    if(pk == 0)
                    begin
                        read <= 1;
                        PC <= PC + 1;
                    end
                    else
                        imm_low <= data_in;
                end

                STATE_IMM_HIGH_READ:
                begin
                    if(pk == 0)
                    begin
                        read <= 1;
                        PC <= PC + 1;
                    end
                    else
                        imm_high <= data_in;
                end

                STATE_EXECUTE:
                begin
                end

                default:
                begin
                end
            endcase
        end
    end

endmodule;

