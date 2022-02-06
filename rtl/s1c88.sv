
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
    output wire write,
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

    // After having been stored in the 16-bit temporary
    // register TEMP 2, the operation result is either
    // stored in the register/memory or used as address
    // data according to the operation instruction.

    // It seems like SC is set only by the ALU on the manual. This means that
    // if you want to set SC you have to go through the ALU. Perhaps
    // there is a specific ALU operation for this.

    // @note: The original implementation would probably have implemented
    // reading of the immediates in microcode, allowing it to put the
    // immediates into the ALU registers at that stage already. It would
    // probably also allow to calculate addresses for data operations.

    // @todo:
    //
    // * Implement unconditional branch instruction 0xF2, CARL qqrr (3 bytes / 6 cycles).

    localparam [1:0]
        BUS_COMMAND_IDLE      = 2'd0,
        BUS_COMMAND_IRQ_READ  = 2'd1,
        BUS_COMMAND_MEM_WRITE = 2'd2,
        BUS_COMMAND_MEM_READ  = 2'd3;

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
        MICRO_TYPE_SJMP = 3'd3;

    localparam
        MICRO_BUS_MEM_READ  = 1'd0,
        MICRO_BUS_MEM_WRITE = 1'd1;

    localparam [4:0]
        MICRO_MOV_NONE     = 5'h00,

        MICRO_MOV_IMM      = 5'h01,
        MICRO_MOV_IMML     = 5'h02,
        MICRO_MOV_IMMH     = 5'h03,

        MICRO_MOV_A        = 5'h04,
        MICRO_MOV_B        = 5'h05,
        MICRO_MOV_BA       = 5'h06,
        MICRO_MOV_H        = 5'h07,
        MICRO_MOV_L        = 5'h08,
        MICRO_MOV_HL       = 5'h09,
        MICRO_MOV_IX       = 5'h0A,
        MICRO_MOV_IY       = 5'h0B,
        MICRO_MOV_SP       = 5'h0C,
        MICRO_MOV_BR       = 5'h0D,
        MICRO_MOV_PC       = 5'h0E,
        MICRO_MOV_PCL      = 5'h0F,
        MICRO_MOV_PCH      = 5'h10,
        MICRO_MOV_NB       = 5'h11,
        MICRO_MOV_CB       = 5'h12,
        MICRO_MOV_SC       = 5'h13,
        MICRO_MOV_EP       = 5'h14,
        MICRO_MOV_XP       = 5'h14,
        MICRO_MOV_YP       = 5'h15,
        MICRO_MOV_ALU_R    = 5'h16,
        MICRO_MOV_ALU_A    = 5'h17,
        MICRO_MOV_ALU_B    = 5'h18;

    localparam [4:0]
        MICRO_ADD_HL    = 5'h00,
        MICRO_ADD_IX    = 5'h01,
        MICRO_ADD_IX_DD = 5'h02,
        MICRO_ADD_IX_L  = 5'h03,
        MICRO_ADD_IY    = 5'h04,
        MICRO_ADD_IY_DD = 5'h05,
        MICRO_ADD_IY_L  = 5'h06,
        MICRO_ADD_BR    = 5'h07,
        MICRO_ADD_HH_LL = 5'h08,
        MICRO_ADD_KK    = 5'h09,
        MICRO_ADD_SP    = 5'h0A,
        MICRO_ADD_SP_DD = 5'h0B;

    localparam [4:0]
        MICRO_ALU_OP_NONE = 5'h0,
        MICRO_ALU_OP_XI   = 5'h1,
        MICRO_ALU_OP_AND  = 5'h2,
        MICRO_ALU_OP_OR   = 5'h3,
        MICRO_ALU_OP_ADD  = 5'h4,
        MICRO_ALU_OP_SUB  = 5'h5,
        MICRO_ALU_OP_INC  = 5'h6,
        MICRO_ALU_OP_INC2 = 5'h7,
        MICRO_ALU_OP_DEC  = 5'h8,
        MICRO_ALU_OP_NEG  = 5'h9,
        MICRO_ALU_OP_ROL  = 5'h10,
        MICRO_ALU_OP_ROR  = 5'h11;

    reg [8:0] translation_rom[0:767];
    //reg [8:0] jump_table[0:15];
    reg [31:0] rom[0:511];

    assign write = pl && pk &&
        (state == STATE_EXECUTE) &&
        (micro_op_type == MICRO_TYPE_BUS) &&
        (micro_bus_op == MICRO_BUS_MEM_WRITE);/* &&
        !microinstruction_done;*/

    initial
    begin
        for (int i = 0; i < 768; i++)
            translation_rom[i] = 0;

        for (int i = 0; i < 512; i++)
            rom[i] = 0;

        // Microinstruction Design Notes:
        // 
        // Currently we allow all microinstructions to set the alu operation.
        // Perhaps it would be better to have microinstructions for the
        // reading of the immediate values too, then you can write the
        // immediate straight where you need it in the next microinstructions.
        // Alternatively, we could have convert bus micros into simple move
        // micros with MICRO_MOV_MEM, but where would we put the addressing
        // mode? In 8086, the address is explicitly set by the
        // microinstructions. Perhaps this could also be a possibility here,
        // but we would need to run the microinstructions on both positive and
        // negative edges, with the negative edge logic indexing into the rom
        // with a 0 offset, while the positive edge logic indexing with an
        // offset of +1.

        rom[0] = {MICRO_TYPE_MISC, 1'b0, MICRO_ALU_OP_NONE, 1'd0, MICRO_MOV_NONE, MICRO_MOV_NONE, 2'b01, MICRO_MOV_NONE, MICRO_MOV_NONE};
        rom[1] = {MICRO_TYPE_BUS, 1'b0, MICRO_ALU_OP_NONE, MICRO_BUS_MEM_READ, MICRO_ADD_BR,    MICRO_MOV_A, 2'b01, MICRO_MOV_NONE, MICRO_MOV_NONE};
        rom[2] = {MICRO_TYPE_BUS, 1'b0, MICRO_ALU_OP_NONE, MICRO_BUS_MEM_READ, MICRO_ADD_HH_LL, MICRO_MOV_A, 2'b01, MICRO_MOV_NONE, MICRO_MOV_NONE};
        rom[3] = {MICRO_TYPE_BUS, 1'b0, MICRO_ALU_OP_NONE, MICRO_BUS_MEM_READ, MICRO_ADD_HL,    MICRO_MOV_A, 2'b01, MICRO_MOV_NONE, MICRO_MOV_NONE};
        rom[4] = {MICRO_TYPE_BUS, 1'b0, MICRO_ALU_OP_NONE, MICRO_BUS_MEM_READ, MICRO_ADD_IX,    MICRO_MOV_A, 2'b01, MICRO_MOV_NONE, MICRO_MOV_NONE};
        rom[5] = {MICRO_TYPE_BUS, 1'b0, MICRO_ALU_OP_NONE, MICRO_BUS_MEM_READ, MICRO_ADD_IY,    MICRO_MOV_A, 2'b01, MICRO_MOV_NONE, MICRO_MOV_NONE};

        rom[6] = {MICRO_TYPE_BUS, 1'b0, MICRO_ALU_OP_NONE, MICRO_BUS_MEM_READ, MICRO_ADD_IX_DD, MICRO_MOV_A, 2'b10, MICRO_MOV_NONE, MICRO_MOV_NONE};
        rom[7] = {MICRO_TYPE_MISC, 1'b0, MICRO_ALU_OP_NONE, 1'd0, MICRO_MOV_NONE, MICRO_MOV_NONE, 2'b01, MICRO_MOV_NONE, MICRO_MOV_NONE};

        rom[8] = {MICRO_TYPE_BUS, 1'b0, MICRO_ALU_OP_NONE, MICRO_BUS_MEM_READ, MICRO_ADD_IY_DD, MICRO_MOV_A, 2'b10, MICRO_MOV_NONE, MICRO_MOV_NONE};
        rom[9] = {MICRO_TYPE_MISC, 1'b0, MICRO_ALU_OP_NONE, 1'd0, MICRO_MOV_NONE, MICRO_MOV_NONE, 2'b01, MICRO_MOV_NONE, MICRO_MOV_NONE};

        rom[10] = {MICRO_TYPE_BUS, 1'b0, MICRO_ALU_OP_NONE, MICRO_BUS_MEM_READ, MICRO_ADD_IX_L, MICRO_MOV_A, 2'b10, MICRO_MOV_NONE, MICRO_MOV_NONE};
        rom[11] = {MICRO_TYPE_MISC, 1'b0, MICRO_ALU_OP_NONE, 1'd0, MICRO_MOV_NONE, MICRO_MOV_NONE, 2'b01, MICRO_MOV_NONE, MICRO_MOV_NONE};

        rom[12] = {MICRO_TYPE_BUS, 1'b0, MICRO_ALU_OP_NONE, MICRO_BUS_MEM_READ, MICRO_ADD_IY_L, MICRO_MOV_A, 2'b10, MICRO_MOV_NONE, MICRO_MOV_NONE};
        rom[13] = {MICRO_TYPE_MISC, 1'b0, MICRO_ALU_OP_NONE, 1'd0, MICRO_MOV_NONE, MICRO_MOV_NONE, 2'b01, MICRO_MOV_NONE, MICRO_MOV_NONE};

        rom[14] = {MICRO_TYPE_MISC, 1'b0, MICRO_ALU_OP_NONE, 1'd0, MICRO_MOV_NONE, MICRO_MOV_NONE, 2'b01, MICRO_MOV_EP, MICRO_MOV_IMM};
        rom[15] = {MICRO_TYPE_MISC, 1'b0, MICRO_ALU_OP_NONE, 1'd0, MICRO_MOV_NONE, MICRO_MOV_NONE, 2'b01, MICRO_MOV_BR, MICRO_MOV_IMM};

        rom[16] = {MICRO_TYPE_BUS, 1'b0, MICRO_ALU_OP_NONE, MICRO_BUS_MEM_WRITE, MICRO_ADD_BR, MICRO_MOV_IMMH, 2'b10, MICRO_MOV_NONE, MICRO_MOV_NONE};
        rom[17] = {MICRO_TYPE_MISC, 1'b0, MICRO_ALU_OP_NONE, 1'd0, MICRO_MOV_NONE, MICRO_MOV_NONE, 2'b01, MICRO_MOV_NONE, MICRO_MOV_NONE};

        rom[18] = {MICRO_TYPE_BUS, 1'b0, MICRO_ALU_OP_OR, MICRO_BUS_MEM_READ, MICRO_ADD_BR, MICRO_MOV_ALU_A, 2'b00, MICRO_MOV_NONE, MICRO_MOV_NONE};
        rom[19] = {MICRO_TYPE_BUS, 1'b0, MICRO_ALU_OP_NONE, MICRO_BUS_MEM_WRITE, MICRO_ADD_BR, MICRO_MOV_ALU_R, 2'b10, MICRO_MOV_NONE, MICRO_MOV_NONE};
        rom[20] = {MICRO_TYPE_MISC, 1'b0, MICRO_ALU_OP_NONE, 1'd0, MICRO_MOV_NONE, MICRO_MOV_NONE, 2'b01, MICRO_MOV_NONE, MICRO_MOV_NONE};

        rom[21] = {MICRO_TYPE_MISC, 1'b0, MICRO_ALU_OP_NONE, 1'd0, MICRO_MOV_NONE, MICRO_MOV_NONE, 2'b10, MICRO_MOV_SC, MICRO_MOV_IMML};
        rom[22] = {MICRO_TYPE_MISC, 1'b0, MICRO_ALU_OP_NONE, 1'd0, MICRO_MOV_NONE, MICRO_MOV_NONE, 2'b01, MICRO_MOV_NONE, MICRO_MOV_NONE};

        rom[23] = {MICRO_TYPE_MISC, 1'b0, MICRO_ALU_OP_NONE, 1'd0, MICRO_MOV_NONE, MICRO_MOV_NONE, 2'b01, MICRO_MOV_SP, MICRO_MOV_IMM};

        // @todo: 3 bus write operations combined with decrementing of SP.
        //        1 misc operation with ALU PC <- PC + qqrr + 2, and mov CB <- NB.
        //        @note: I think we might need another ALU operation to add
        //        the 2?
        //
        //  There are two questions, though. How do I make sure PC and qqnn
        //  are in the ALU A and B registers, respectively, and how do we move
        //  the ALU result back to PC.
        rom[24] = {MICRO_TYPE_BUS, 1'b0, MICRO_ALU_OP_NONE, MICRO_BUS_MEM_WRITE, MICRO_ADD_SP, MICRO_MOV_CB,  2'b00, MICRO_MOV_ALU_A, MICRO_MOV_IMM};
        rom[25] = {MICRO_TYPE_BUS, 1'b1, MICRO_ALU_OP_INC2, MICRO_BUS_MEM_WRITE, MICRO_ADD_SP, MICRO_MOV_PCH, 2'b00, MICRO_MOV_ALU_B, MICRO_MOV_ALU_R};
        rom[26] = {MICRO_TYPE_BUS, 1'b0, MICRO_ALU_OP_NONE, MICRO_BUS_MEM_WRITE, MICRO_ADD_SP, MICRO_MOV_PCL, 2'b10, MICRO_MOV_ALU_A, MICRO_MOV_PC};
        rom[27] = {MICRO_TYPE_MISC, 1'b1, MICRO_ALU_OP_ADD, 1'd0, MICRO_MOV_NONE, MICRO_MOV_NONE, 2'b01, MICRO_MOV_PC, MICRO_MOV_ALU_R};

        translation_rom[10'h044] = 1;
        translation_rom[10'h1D0] = 2;
        translation_rom[10'h045] = 3;
        translation_rom[10'h046] = 4;
        translation_rom[10'h047] = 5;
        translation_rom[10'h140] = 6;
        translation_rom[10'h141] = 8;
        translation_rom[10'h142] = 10;
        translation_rom[10'h143] = 12;

        translation_rom[10'h1C5] = 14;
        translation_rom[10'h0B4] = 15;
        translation_rom[10'h0DD] = 16;

        translation_rom[10'h0D9] = 18;
        translation_rom[10'h09F] = 21;

        translation_rom[10'h26E] = 23;

        translation_rom[10'h0F2] = 24;

    end

    reg [15:0] BA;
    reg [7:0] EP;
    reg [7:0] BR;
    reg [7:0] SC;
    reg [15:0] SP;
    wire [7:0] A = BA[7:0];
    wire [7:0] B = BA[15:8];

    reg [4:0] alu_op;
    reg alu_size;
    reg [15:0] alu_A;
    reg [15:0] alu_B;
    wire [15:0] alu_R;
    wire [5:0] alu_flags;

    alu alu
    (
        alu_op,
        alu_size,
        alu_A, alu_B, alu_R,
        alu_flags
    );

    wire [31:0] micro_op = rom[microaddress + {5'd0, microprogram_counter}];
    wire [4:0] micro_mov_src = micro_op[4:0];
    wire [4:0] micro_mov_dst = micro_op[9:5];

    wire microinstruction_done = micro_op[10];
    wire microinstruction_nearly_done = micro_op[11];

    wire [4:0] micro_bus_reg = micro_op[16:12];
    wire [4:0] micro_bus_add = micro_op[21:17];
    wire micro_bus_op = micro_op[22];

    wire [4:0] micro_alu_op = micro_op[27:23];
    wire micro_alu_size = micro_op[28];

    wire [2:0] micro_op_type = micro_op[31:29];

    reg [3:0] microprogram_counter;
    reg [8:0] microaddress;

    reg [15:0] src_reg;
    always_comb
    begin
        case(micro_mov_src)
            MICRO_MOV_IMM:
                src_reg = imm;

            MICRO_MOV_IMML:
                src_reg = {8'd0, imm_low};

            MICRO_MOV_IMMH:
                src_reg = {8'd0, imm_high};

            MICRO_MOV_A:
                src_reg = {8'd0, A};

            MICRO_MOV_B:
                src_reg = {8'd0, B};

            MICRO_MOV_BA:
                src_reg = BA;

            MICRO_MOV_ALU_A:
                src_reg = alu_A;

            MICRO_MOV_ALU_B:
                src_reg = alu_B;

            MICRO_MOV_ALU_R:
                src_reg = alu_R;

            //MICRO_MOV_H     = 5'h07,
            //MICRO_MOV_L     = 5'h08,
            //MICRO_MOV_HL    = 5'h09,
            //MICRO_MOV_IX    = 5'h0A,
            //MICRO_MOV_IY    = 5'h0B,
            //MICRO_MOV_SP    = 5'h0C,
            MICRO_MOV_SC:
                src_reg = {8'd0, SC};

            MICRO_MOV_BR:
                src_reg = {8'd0, BR};

            MICRO_MOV_PC:
                src_reg = PC;

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
    wire alu_b_imm8;
    wire alu_b_imm16;

    decode decode_inst
    (
        .opcode,
        .opext,
        .need_opext,
        .need_imm,
        .imm_size,
        .alu_b_imm8,
        .alu_b_imm16
    );

    assign sync = fetch_opcode;
    reg fetch_opcode;
    wire opcode_error = (microaddress == 0 && state == STATE_EXECUTE);
    wire [7:0] opcode_extension = opcode - 8'hCD;
    wire [9:0] extended_opcode = need_opext?
        {opcode_extension[1:0], opext}:
        {2'd0, opcode};

    always_ff @ (negedge clk, posedge reset)
    begin
        if(reset)
        begin
        end
        else if(pl == 1)
        begin
            alu_size <= micro_alu_size;
            // @todo: We probably need to add flag for updating flags
            // or not.
            //alu_flags_r <= alu_flags;

            case(micro_alu_op)
                MICRO_ALU_OP_AND:
                    alu_op <= ALUOP_AND;

                MICRO_ALU_OP_ADD:
                    alu_op <= ALUOP_ADD;

                MICRO_ALU_OP_SUB:
                    alu_op <= ALUOP_SUB;

                MICRO_ALU_OP_INC:
                    alu_op <= ALUOP_INC;

                MICRO_ALU_OP_INC2:
                    alu_op <= ALUOP_INC2;

                MICRO_ALU_OP_DEC:
                    alu_op <= ALUOP_DEC;

                MICRO_ALU_OP_NEG:
                    alu_op <= ALUOP_NEG;

                MICRO_ALU_OP_ROL:
                    alu_op <= ALUOP_ROL;

                MICRO_ALU_OP_ROR:
                    alu_op <= ALUOP_ROR;

                default:
                    alu_op <= 0;

            endcase
        end
    end



    always_ff @ (negedge clk, posedge reset)
    begin
        if(reset)
        begin
            iack                 <= 0;
            state                <= STATE_IDLE;
            address_out          <= ~0;
            pl                   <= 0;
            bus_status           <= BUS_COMMAND_IDLE;
            reset_counter        <= 0;
            exception            <= EXCEPTION_TYPE_RESET;
            fetch_opcode         <= 0;
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
            if(pl == 0)
            begin
                if(next_state == STATE_EXECUTE)
                begin
                    if(alu_b_imm8)
                    begin
                        // Simply take the last requested byte. #nn is always
                        // the last instruction byte.
                        alu_B <= {8'h0, data_in};
                    end
                    if(alu_b_imm16)
                    begin
                        alu_B <= imm;
                    end
                end

                if(fetch_opcode)
                begin
                    opcode <= data_in;
                end
            end
            else if(pl == 1)
            begin
                address_out <= {9'b0, PC[14:0]};
                state <= next_state;
                bus_status <= BUS_COMMAND_MEM_READ;
                fetch_opcode <= 0;

                if(next_state == STATE_EXECUTE)
                begin
                    if(microinstruction_done && exception == EXCEPTION_TYPE_NONE)
                        fetch_opcode <= 1;
                end

                if(exception != EXCEPTION_TYPE_NONE && iack == 0)
                begin
                    iack                   <= 1;
                    fetch_opcode           <= 1;
                    address_out            <= 24'hDEFACE;
                    exception_process_step <= 0;
                end
            end


            if(state == STATE_EXC_PROCESS)
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
                        fetch_opcode <= 1;
                    end
                end
            end
            else if(state == STATE_OPEXT_READ)
            begin
                if(pl == 0)
                    opext <= data_in;
            end
            else if(
                state == STATE_EXECUTE ||
                next_state == STATE_EXECUTE
            )
            begin
                if(pl == 1)
                begin

                    if(state == STATE_EXECUTE)
                    begin
                        if(!fetch_opcode)
                        begin
                            state <= STATE_EXECUTE;
                            if(microinstruction_done)
                                fetch_opcode <= 1;
                        end

                        if(micro_op_type == MICRO_TYPE_BUS && micro_bus_op == MICRO_BUS_MEM_READ)
                        begin
                            case(micro_bus_reg)
                                MICRO_MOV_ALU_A:
                                begin
                                    alu_A <= {8'd0, data_in};
                                end
                                MICRO_MOV_ALU_B:
                                begin
                                    alu_B <= {8'd0, data_in};
                                end
                                default:
                                begin
                                end
                            endcase
                        end
                    end

                    // Don't do any bus ops on the last microinstruction
                    // step.
                    if(!microinstruction_done || state != STATE_EXECUTE)
                    begin
                        if(micro_op_type == MICRO_TYPE_BUS)
                        begin
                            if(micro_bus_op == MICRO_BUS_MEM_WRITE)
                                bus_status <= BUS_COMMAND_MEM_WRITE;

                            case(micro_bus_add)
                                MICRO_ADD_HH_LL:
                                begin
                                    address_out <= {8'b0, imm};
                                end
                                MICRO_ADD_SP:
                                begin
                                    if(micro_bus_op == MICRO_BUS_MEM_WRITE)
                                    begin
                                        address_out <= {8'b0, SP-16'd1};
                                        SP <= SP - 16'd1;
                                    end
                                    else
                                    begin
                                        address_out <= {8'b0, SP};
                                        SP <= SP + 16'd1;
                                    end
                                end
                                MICRO_ADD_BR:
                                begin
                                    address_out <= {8'b0, BR, imm_low};
                                end
                                default:
                                begin
                                end
                            endcase
                        end
                    end
                end
                else
                begin
                    if(state == STATE_EXECUTE)
                    begin
                        case(micro_mov_dst)
                            MICRO_MOV_EP:
                                EP <= src_reg[7:0];

                            MICRO_MOV_BR:
                                BR <= src_reg[7:0];

                            MICRO_MOV_SC:
                                SC <= src_reg[7:0];

                            MICRO_MOV_SP:
                                SP <= src_reg;

                            MICRO_MOV_ALU_A:
                                alu_A <= src_reg;

                            MICRO_MOV_ALU_B:
                                alu_B <= src_reg;

                            default:
                            begin
                            end
                        endcase
                    end
                end
            end

        end
    end

    // @todo: Try moving PC assigments to negedge clk.
    always_ff @ (posedge clk, posedge reset)
    begin
        if(reset)
        begin
            data_out      <= ~0;
            read          <= 0;
            pk            <= 0;
            microaddress  <= 0;
            microprogram_counter <= 0;
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
            end

            if(next_state == STATE_EXECUTE)
            begin
                if(pk == 1)
                begin
                    microprogram_counter <= 0;
                    microaddress <= translation_rom[extended_opcode];
                end
                else
                begin
                end
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
                        read <= 1;
                        PC <= PC + 1;
                    end
                end

                STATE_IMM_LOW_READ:
                begin
                    if(pk == 0)
                    begin
                        read <= 1;
                        PC <= PC + 1;
                    end
                    else
                    begin
                        // @todo: Move to nededge clk
                        imm_low <= data_in;
                    end
                end

                STATE_IMM_HIGH_READ:
                begin
                    if(pk == 0)
                    begin
                        read <= 1;
                        PC <= PC + 1;
                    end
                    else
                    begin
                        // @todo: Move to nededge clk
                        imm_high <= data_in;
                    end
                end

                STATE_EXECUTE:
                begin
                    if(!microinstruction_done && pk == 1)
                    begin
                        microprogram_counter <= microprogram_counter + 1;
                    end

                    if(micro_mov_dst == MICRO_MOV_PC && pk == 0)
                    begin
                        PC <= src_reg;
                    end

                    if(micro_op_type == MICRO_TYPE_BUS)
                    begin
                        if(micro_bus_op == MICRO_BUS_MEM_READ)
                        begin
                            if(pk == 0)
                            begin
                                read <= 1;
                            end
                        end
                        else // MICRO_BUS_MEM_WRITE
                        begin
                            if(pk == 0)
                            begin
                                case(micro_bus_reg)
                                    MICRO_MOV_ALU_A:
                                    begin
                                        data_out <= alu_A[7:0];
                                    end
                                    MICRO_MOV_ALU_B:
                                    begin
                                        data_out <= alu_B[7:0];
                                    end
                                    MICRO_MOV_ALU_R:
                                    begin
                                        data_out <= alu_R[7:0];
                                    end
                                    MICRO_MOV_IMML:
                                    begin
                                        data_out <= imm_low;
                                    end
                                    MICRO_MOV_IMMH:
                                    begin
                                        data_out <= imm_high;
                                    end
                                    default:
                                    begin
                                    end
                                endcase
                            end
                        end
                    end
                end

                default:
                begin
                end
            endcase
        end
    end

endmodule

