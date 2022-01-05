
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
    output wire sync,
    output logic iack
);
    //In the S1C88, the fetching of the first operation
    //code of the instruction is done overlapping the last
    //cycle of the immediately prior instruction.
    //Consequently, the execution cycle for 1 instruction
    //of the S1C88 begins either from the fetch cycle for
    //the second op-code, the read cycle for the first
    //operand or the first execution cycle (varies depend-
    //ing on the instruction) and terminates with the
    //fetch cycle for the first op-code of the following
    //instruction. 1 cycle instruction only becomes the
    //fetch cycle of the first op-code of the following
    //instruction. In addition, there are also instances
    //where it shifts to the fetch cycle of the first op-code
    //rather than interposing an execute cycle after an
    //operand read cycle.

    enum [1:0]
    {
        BUS_COMMAND_IDLE      = 2'd0,
        BUS_COMMAND_IRQ_READ  = 2'd1,
        BUS_COMMAND_MEM_WRITE = 2'd2,
        BUS_COMMAND_MEM_READ  = 2'd3
    } BusCommand;

    localparam [2:0]
        STATE_IDLE          = 3'd0,
        STATE_OPEXT_READ    = 3'd1,
        STATE_IMM_LOW_READ  = 3'd2,
        STATE_IMM_HIGH_READ = 3'd3,
        STATE_EXECUTE       = 3'd4,
        STATE_EXC_PROCESS   = 3'd5;

    localparam [2:0]
        EXCEPTION_TYPE_RESET   = 3'd0,
        EXCEPTION_TYPE_DIVZERO = 3'd1,
        EXCEPTION_TYPE_NMI     = 3'd2,
        EXCEPTION_TYPE_IRQ3    = 3'd3,
        EXCEPTION_TYPE_IRQ2    = 3'd4,
        EXCEPTION_TYPE_IRQ1    = 3'd5,
        EXCEPTION_TYPE_NONE    = 3'd6;

    localparam [2:0]
        MICRO_TYPE_MISC = 3'd0,
        MICRO_TYPE_BUS  = 3'd1,
        MICRO_TYPE_JMP  = 3'd2,
        MICRO_TYPE_ALU  = 3'd3,
        MICRO_TYPE_SJMP = 3'd4;

    localparam
        MICRO_BUS_MEM_READ  = 1'd0,
        MICRO_BUS_MEM_WRITE = 1'd1;

    localparam [4:0]
        MICRO_MOV_NONE  = 5'h00,

        // register specified by 3 lower bits of opcode.
        MICRO_MOV_R     = 5'h01,
        // memory specified by 3 lower bits of opcode.
        MICRO_MOV_M     = 5'h02,

        MICRO_MOV_IMM   = 5'h03,

        MICRO_MOV_A     = 5'h04,
        MICRO_MOV_B     = 5'h05,
        MICRO_MOV_BA    = 5'h06,
        MICRO_MOV_H     = 5'h07,
        MICRO_MOV_L     = 5'h08,
        MICRO_MOV_HL    = 5'h09,
        MICRO_MOV_IX    = 5'h0A,
        MICRO_MOV_IY    = 5'h0B,
        MICRO_MOV_SP    = 5'h0C,
        MICRO_MOV_BR    = 5'h0D,
        MICRO_MOV_PC    = 5'h0E,
        MICRO_MOV_NB    = 5'h0F,
        MICRO_MOV_CB    = 5'h10,
        MICRO_MOV_EP    = 5'h11,
        MICRO_MOV_XP    = 5'h11,
        MICRO_MOV_YP    = 5'h12,
        MICRO_MOV_ALU_R = 5'h13;

    localparam [4:0]
        MICRO_ALU_OP_NONE = 5'h0,
        MICRO_ALU_OP_XI   = 5'h1,
        MICRO_ALU_OP_AND  = 5'h2,
        MICRO_ALU_OP_ADD  = 5'h3,
        MICRO_ALU_OP_SUB  = 5'h4,
        MICRO_ALU_OP_INC  = 5'h5,
        MICRO_ALU_OP_DEC  = 5'h6,
        MICRO_ALU_OP_NEG  = 5'h7,
        MICRO_ALU_OP_ROL  = 5'h8,
        MICRO_ALU_OP_ROR  = 5'h9;

    reg [8:0] translation_rom[0:767];
    //reg [8:0] jump_table[0:15];
    reg [18:0] rom[0:511];

    initial
    begin
        for (int i = 0; i < 768; i++)
            translation_rom[i] = 0;

        for (int i = 0; i < 512; i++)
            rom[i] = 0;

        rom[0] = {MICRO_TYPE_BUS, 4'd0, MICRO_BUS_MEM_READ, 1'b1, MICRO_MOV_A, MICRO_MOV_BR};
        rom[1] = {MICRO_TYPE_BUS, 4'd0, MICRO_BUS_MEM_READ, 1'b1, MICRO_MOV_A, MICRO_MOV_IMM};
        rom[2] = {MICRO_TYPE_BUS, 4'd0, MICRO_BUS_MEM_READ, 1'b1, MICRO_MOV_A, MICRO_MOV_HL};
        rom[3] = {MICRO_TYPE_BUS, 4'd0, MICRO_BUS_MEM_READ, 1'b1, MICRO_MOV_A, MICRO_MOV_IX};
        rom[4] = {MICRO_TYPE_BUS, 4'd0, MICRO_BUS_MEM_READ, 1'b1, MICRO_MOV_A, MICRO_MOV_IY};

        rom[5] = {MICRO_TYPE_ALU, MICRO_ALU_OP_ADD, 1'b0, MICRO_MOV_IX, MICRO_MOV_IMM};
        rom[6] = {MICRO_TYPE_BUS, 4'd0, MICRO_BUS_MEM_READ, 1'b1, MICRO_MOV_A, MICRO_MOV_ALU_R};

        rom[7] = {MICRO_TYPE_ALU, MICRO_ALU_OP_ADD, 1'b0, MICRO_MOV_IY, MICRO_MOV_IMM};
        rom[8] = {MICRO_TYPE_BUS, 4'd0, MICRO_BUS_MEM_READ, 1'b1, MICRO_MOV_A, MICRO_MOV_ALU_R};

        rom[9] = {MICRO_TYPE_ALU, MICRO_ALU_OP_ADD, 1'b0, MICRO_MOV_IX, MICRO_MOV_L};
        rom[10] = {MICRO_TYPE_BUS, 4'd0, MICRO_BUS_MEM_READ, 1'b1, MICRO_MOV_A, MICRO_MOV_ALU_R};

        rom[11] = {MICRO_TYPE_ALU, MICRO_ALU_OP_ADD, 1'b0, MICRO_MOV_IY, MICRO_MOV_L};
        rom[12] = {MICRO_TYPE_BUS, 4'd0, MICRO_BUS_MEM_READ, 1'b1, MICRO_MOV_A, MICRO_MOV_ALU_R};

        rom[13] = {MICRO_TYPE_MISC, 5'd0, 1'b1, MICRO_MOV_EP, MICRO_MOV_IMM};
        rom[14] = {MICRO_TYPE_MISC, 5'd0, 1'b1, MICRO_MOV_BR, MICRO_MOV_IMM};

        translation_rom[10'h044] = 0;
        translation_rom[10'h1D0] = 1;
        translation_rom[10'h045] = 2;
        translation_rom[10'h046] = 3;
        translation_rom[10'h047] = 4;
        translation_rom[10'h140] = 5;
        translation_rom[10'h141] = 7;
        translation_rom[10'h142] = 9;
        translation_rom[10'h143] = 11;

        translation_rom[10'h1C5] = 13;
        translation_rom[10'h0B4] = 14;

    end

    reg [15:0] BA;
    reg [7:0] EP;
    reg [7:0] BR;
    wire [7:0] A = BA[7:0];
    wire [7:0] B = BA[15:8];

    wire [18:0] micro_op = rom[microaddress + {5'd0, microprogram_counter}];
    wire [4:0] micro_mov_src = micro_op[4:0];
    wire [4:0] micro_mov_dst = micro_op[9:5];
    wire microinstruction_done = micro_op[10];
    wire [2:0] micro_op_type = micro_op[18:16];
    wire micro_bus_op = micro_op[11];

    reg [3:0] microprogram_counter;
    reg [8:0] microaddress;

    reg [15:0] src_reg;
    always_comb
    begin
        case(micro_mov_src)
            MICRO_MOV_IMM:
                src_reg = imm;

            MICRO_MOV_A:
                src_reg = {8'd0, A};

            MICRO_MOV_B:
                src_reg = {8'd0, B};

            MICRO_MOV_BA:
                src_reg = BA;

            //MICRO_MOV_H     = 5'h07,
            //MICRO_MOV_L     = 5'h08,
            //MICRO_MOV_HL    = 5'h09,
            //MICRO_MOV_IX    = 5'h0A,
            //MICRO_MOV_IY    = 5'h0B,
            //MICRO_MOV_SP    = 5'h0C,
            //MICRO_MOV_SC    = 5'h0C,
            MICRO_MOV_BR:
                src_reg = {8'd0, BR};
            //MICRO_MOV_PC    = 5'h0E,
            //MICRO_MOV_NB    = 5'h0F,
            //MICRO_MOV_CB    = 5'h10,
            MICRO_MOV_EP:
                src_reg = {8'd0, EP};
            //MICRO_MOV_XP    = 5'h11,
            //MICRO_MOV_YP    = 5'h12,
            default:
                src_reg = 0;
        endcase
    end

    reg [2:0] state = STATE_IDLE;

    wire [2:0] next_state =
        (state == STATE_IDLE)?
            (exception != EXCEPTION_TYPE_NONE ? STATE_EXC_PROCESS:
                                                STATE_EXECUTE):

        (state == STATE_EXC_PROCESS) ?
            (need_opext                       ? STATE_OPEXT_READ:
            (need_imm                         ? STATE_IMM_LOW_READ:
                                                STATE_EXECUTE)):

        (state == STATE_EXECUTE) ?
            (need_opext                       ? STATE_OPEXT_READ:
            (need_imm                         ? STATE_IMM_LOW_READ:
            (exception != EXCEPTION_TYPE_NONE ? STATE_EXC_PROCESS:
                                                STATE_EXECUTE))):

        (state == STATE_OPEXT_READ) ?
            (need_imm    ? STATE_IMM_LOW_READ:
                           STATE_EXECUTE):

        (state == STATE_IMM_LOW_READ) ?
            (imm_size    ? STATE_IMM_HIGH_READ:
                           STATE_EXECUTE):
                           STATE_EXECUTE;

    reg [15:0] PC = 16'hFACE;

    reg [7:0] opcode;
    reg [7:0] opext;
    reg [7:0] imm_low;
    reg [7:0] imm_high;
    wire [15:0] imm = {imm_high, imm_low};

    reg [1:0] reset_counter;
    reg [2:0] exception = EXCEPTION_TYPE_NONE;

    reg [2:0] exception_process_step;

    wire imm_size;
    wire need_opext;
    wire need_imm;
    wire decode_error;

    decode decode_inst
    (
        .opcode,
        .opext,

        .need_opext,
        .need_imm,
        .imm_size,
        .error(decode_error)
    );

    // @todo: In a real system, we may need to align this to an edge.
    assign sync = fetch_opcode;
    reg fetch_opcode;
    wire opcode_error = (microaddress == 0 && state == STATE_EXECUTE);
    wire [7:0] opcode_extension = opcode - 8'hCD;
    wire [9:0] extended_opcode = need_opext?
        {opcode_extension[1:0], opext}:
        {2'd0, opcode};

    // @note: Perhaps I would be happier if we had a opcode fetcher. Whenever
    // it's empty, request an opcode fetch. When done with an opcode, evacuate
    // and request a new one. Anyway, just keep in mind that the code below
    // could be a bit fragile.
    always_comb
    begin
        // @todo: After a reset, fetch_opcode depends on microinstruction_done
        // being set to 1, but there is no microinstruction loaded yet!
        if(state == STATE_EXECUTE && microinstruction_done)
            fetch_opcode = 1;
        else if(exception_process_step == 0 && iack == 1)
            fetch_opcode = 1;
        else
            fetch_opcode = 0;
    end

    always_ff @ (negedge clk, posedge reset)
    begin
        if(reset)
        begin
            iack          <= 0;
            state         <= STATE_IDLE;
            address_out   <= ~0;
            data_out      <= ~0;
            write         <= 0;
            pl            <= 0;
            bus_status    <= BUS_COMMAND_IDLE;
            reset_counter <= 0;
            exception     <= EXCEPTION_TYPE_RESET;
            //fetch_opcode  <= 0;

            microprogram_counter <= 0;
            microaddress         <= 0;
        end
        else if(reset_counter < 2)
        begin
            reset_counter <= reset_counter + 1;
            if(reset_counter == 1)
            begin
                // Output dummy address
                address_out <= 24'hDEFACE;
                exception_process_step <= 0;
            end
        end
        else
        begin
            pl <= ~pl;

            if(pl == 1)
            begin
                address_out <= {9'b0, PC[14:0]};
                state <= next_state;
                bus_status <= BUS_COMMAND_MEM_READ;

                if(exception != EXCEPTION_TYPE_NONE)
                begin
                    iack <= 1;
                    address_out <= 24'hDEFACE;
                end

                if(next_state == STATE_EXECUTE)
                    microaddress <= translation_rom[extended_opcode];
            end


            case(state)
                STATE_EXC_PROCESS:
                begin
                    if(pl == 1)
                    begin
                        exception_process_step <= exception_process_step + 1;
                        state <= STATE_EXC_PROCESS;

                        if(exception_process_step == 1)
                        begin
                            address_out <= 0;
                        end
                        else if(exception_process_step == 2)
                        begin
                            address_out <= 1;
                            exception   <= EXCEPTION_TYPE_NONE;
                            iack        <= 0;
                        end
                        else if(exception_process_step == 3)
                        begin
                            state <= next_state;
                        end
                    end
                end
                STATE_OPEXT_READ:
                begin
                end
                STATE_EXECUTE:
                begin
                    if(!microinstruction_done)
                    begin
                        state <= STATE_EXECUTE;
                        microprogram_counter <= microprogram_counter + 1;
                    end

                    if(micro_op_type == MICRO_TYPE_BUS)
                    begin
                        if(pl == 1)
                        begin
                            case(micro_mov_src)
                                MICRO_MOV_IMM:
                                begin
                                    address_out <= {8'b0, imm};
                                end
                                default:
                                begin
                                end
                            endcase
                        end
                    end
                    else if(micro_op_type == MICRO_TYPE_MISC)
                    begin
                        if(pl == 1)
                        begin
                            case(micro_mov_dst)
                                MICRO_MOV_EP:
                                    EP <= src_reg[7:0];
                                MICRO_MOV_BR:
                                    BR <= src_reg[7:0];
                                default:
                                begin
                                end
                            endcase
                        end
                    end
                end
                default:
                begin
                end
            endcase

        end
    end

    always_ff @ (posedge clk, posedge reset)
    begin
        if(reset)
        begin
            read          <= 0;
            pk            <= 0;
        end
        else if(reset_counter >= 2)
        begin
            pk <= ~pk;
            read <= 0;

            if(fetch_opcode)
            begin
                if(pk == 0)
                begin
                    read <= 1;
                    PC <= PC + 1;
                end
                else
                    opcode <= data_in;
            end

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
                        if(exception_process_step == 2)
                        begin
                            PC[7:0] <= data_in;
                        end
                        else if(exception_process_step == 3)
                        begin
                            PC[15:8] <= data_in;
                        end
                    end
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
                    if(pk == 0)
                    begin
                        // Set read or write depending on op
                    end
                    else
                    begin
                        // Read or write data depending on op.
                    end
                end

                default:
                begin
                end
            endcase
        end
    end

endmodule;

