
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

    // @note: If we moved IMM automatically into alu A (i.e. during
    // decoding), then we could have moved performed all alu operations
    // one micro earlier, meaning that we could have modified PC one micro
    // earlier. See example microprogram:
    //
    // rom[24] = {MICRO_TYPE_BUS, 1'b1, MICRO_ALU_OP_ADD, MICRO_BUS_MEM_WRITE, MICRO_ADD_SP, MICRO_MOV_CB,  2'b00, MICRO_MOV_ALU_A, MICRO_MOV_PC};
    // rom[25] = {MICRO_TYPE_BUS, 1'b1, MICRO_ALU_OP_INC2, MICRO_BUS_MEM_WRITE, MICRO_ADD_SP, MICRO_MOV_PCH, 2'b00, MICRO_MOV_ALU_A, MICRO_MOV_ALU_R};
    // rom[26] = {MICRO_TYPE_BUS, 1'b0, MICRO_ALU_OP_NONE MICRO_BUS_MEM_WRITE, MICRO_ADD_SP, MICRO_MOV_PCL, 2'b10, MICRO_MOV_NONE, MICRO_MOV_NONE};
    // rom[27] = {MICRO_TYPE_MISC, 1'b0, MICRO_ALU_OP_NONE, 1'd0, MICRO_MOV_NONE, MICRO_MOV_NONE, 2'b01, MICRO_MOV_PC, MICRO_MOV_ALU_R};
    //
    // I guess we will see at a later point if we need to change where PC
    // is being set again. Note, though that we still have to set PC in
    // the last micro, and since we want to overlap instructions, the
    // window that is left for PC to change on time for an opcode fetch is
    // narrow, leaving (I think) only the possibility of updating PC at
    // PL == 1.
    //

    // @todo:
    //
    // * Implement jump instructions (JRS NZ 0xE7). -- We just need to
    //   implement the if branch and hardcode the else.
    // * I think we need to remove the imm reading from the decoder and move
    //   that to the microinstructions. that will allow us to run more
    //   operations. This seems to be required for some ops like AND A, #nn.
    // * Use the correct page register depending on addressing mode.
    // * Check if we still need to add NOP after bus operation if it's the
    //   last micro. -- We can probably think of ways to implement this, but
    //   for now we will continue using the nops. It's easy to remove them in
    //   the future if we decide to do this.

    // For jump instruction we need: condition, offset (TA1/TA2). I think
    // we'll leave the mov instructions in there as common to all
    // instructions.
    // We can infer rr/qqrr from imm_size (not sure if we need to latch it).
    // 2-byte instructions use TA1, 3-byte instructions use TA2. So either we
    // set it in the micro since we have space, or infer by looking if
    // imm_size == 1 or extended_opcode[9:8] != 0. That would mean we don't
    // even need the offset, only the condition. We do save logic, though, by
    // putting that in the micro.
    //
    // Conditions:
    //     __cc2__
    //     * N^V=1      ; Less
    //     * N^V=0      ; Grater
    //     * Z|[N^V]=1  ; Less or equal
    //     * Z|[N^V]=0  ; Greater or equal
    //     * V=1        ; Overflow
    //     * V=0        ; No Overflow
    //     * N=1        ; Minus
    //     * N=0        ; Plus
    //     * F0=1       ; F0 is set
    //     * F0=0       ; F0 is reset
    //     * F1=1       ; F1 is set
    //     * F1=0       ; F1 is reset
    //     * F2=1       ; F2 is set
    //     * F2=0       ; F2 is reset
    //     * F3=1       ; F3 is set
    //     * F3=0       ; F3 is reset
    //
    //     __cc1__
    //     * C=1        ; Carry
    //     * C=0        ; Non Carry
    //     * Z=1        ; Zero
    //     * Z=0        ; Non Zero
    //
    //     __other__
    //     * B=0
    //
    // Total 21 conditions, 5 bits are enough.
    //
    // @note: Perhaps MICRO_MOV_TA1/2 are not required after implementing the
    // jump micro.

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
        MICRO_TYPE_JMP  = 3'd2;

    localparam [2:0]
        MICRO_NOT_DONE    = 3'b00,
        MICRO_DONE        = 3'b01,
        MICRO_NEARLY_DONE = 3'b10;

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
        MICRO_MOV_IXH      = 5'h0B,
        MICRO_MOV_IXL      = 5'h0C,
        MICRO_MOV_IY       = 5'h0D,
        MICRO_MOV_IYH      = 5'h0E,
        MICRO_MOV_IYL      = 5'h0F,
        MICRO_MOV_SP       = 5'h10,
        MICRO_MOV_BR       = 5'h11,
        MICRO_MOV_PC       = 5'h12,
        MICRO_MOV_PCL      = 5'h13,
        MICRO_MOV_PCH      = 5'h14,
        MICRO_MOV_TA1      = 5'h15,
        MICRO_MOV_TA2      = 5'h16,
        MICRO_MOV_NB       = 5'h17,
        MICRO_MOV_CB       = 5'h18,
        MICRO_MOV_SC       = 5'h19,
        MICRO_MOV_EP       = 5'h1A,
        MICRO_MOV_XP       = 5'h1B,
        MICRO_MOV_YP       = 5'h1C,
        MICRO_MOV_ALU_R    = 5'h1D,
        MICRO_MOV_ALU_A    = 5'h1E,
        MICRO_MOV_ALU_B    = 5'h1F;

    // @note: Can probably reduce some resource usage by making all *1 address
    // micros be at an odd address.
    localparam [4:0]
        MICRO_ADD_HL     = 5'h00,
        MICRO_ADD_HL1    = 5'h01,
        MICRO_ADD_IX     = 5'h02,
        MICRO_ADD_IX1    = 5'h03,
        MICRO_ADD_IX_DD  = 5'h04,
        MICRO_ADD_IX_L   = 5'h05,
        MICRO_ADD_IY     = 5'h06,
        MICRO_ADD_IY1    = 5'h07,
        MICRO_ADD_IY_DD  = 5'h08,
        MICRO_ADD_IY_L   = 5'h09,
        MICRO_ADD_BR     = 5'h0A,
        MICRO_ADD_BR1    = 5'h0B,
        MICRO_ADD_HH_LL  = 5'h0C,
        MICRO_ADD_HH_LL1 = 5'h0D,
        MICRO_ADD_KK     = 5'h0E,
        MICRO_ADD_SP     = 5'h0F,
        MICRO_ADD_SP_DD  = 5'h10,
        MICRO_ADD_SP_DD1 = 5'h11;

    localparam [4:0]
        MICRO_ALU_OP_NONE = 5'h0,
        MICRO_ALU_OP_XOR  = 5'h1,
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

    localparam [4:0]
        MICRO_COND_NONE          = 5'h00,
        MICRO_COND_LESS          = 5'h01,
        MICRO_COND_GREATER       = 5'h02,
        MICRO_COND_LESS_EQUAL    = 5'h03,
        MICRO_COND_GREATER_EQUAL = 5'h04,
        MICRO_COND_OVERFLOW      = 5'h05,
        MICRO_COND_NON_OVERFLOW  = 5'h06,
        MICRO_COND_MINUS         = 5'h07,
        MICRO_COND_PLUS          = 5'h08,
        MICRO_COND_CARRY         = 5'h09,
        MICRO_COND_NON_CARRY     = 5'h0A,
        MICRO_COND_ZERO          = 5'h0B,
        MICRO_COND_NON_ZERO      = 5'h0C,
        MICRO_COND_F0_SET        = 5'h0D,
        MICRO_COND_F0_RST        = 5'h0E,
        MICRO_COND_F1_SET        = 5'h0F,
        MICRO_COND_F1_RST        = 5'h10,
        MICRO_COND_F2_SET        = 5'h11,
        MICRO_COND_F2_RST        = 5'h12,
        MICRO_COND_F3_SET        = 5'h13,
        MICRO_COND_F3_RST        = 5'h14,
        MICRO_COND_B_IS_ZERO     = 5'h15;

    reg [8:0] translation_rom[0:767];
    reg [31:0] rom[0:511];

    assign write = pl && pk &&
        (state == STATE_EXECUTE) &&
        (micro_op_type == MICRO_TYPE_BUS) &&
        (micro_bus_op == MICRO_BUS_MEM_WRITE);/* &&
        !microinstruction_done;*/

    initial
    begin
        $readmemh("translation_rom.mem", translation_rom);
        $readmemh("rom.mem", rom);
    end

    reg [15:0] BA;
    reg [7:0] EP;
    reg [7:0] XP;
    reg [7:0] YP;
    reg [7:0] BR;
    reg [7:0] SC;
    reg [7:0] CB;
    reg [7:0] NB;
    reg [15:0] SP;
    reg [15:0] HL;
    reg [15:0] IX;
    reg [15:0] IY;
    wire [7:0] A = BA[7:0];
    wire [7:0] B = BA[15:8];

    wire flag_zero     = SC[0];
    wire flag_carry    = SC[1];
    wire flag_overflow = SC[2];
    wire flag_negative = SC[3];
    wire flag_decimal  = SC[4];
    wire flag_unpack   = SC[5];
    wire flag_i0       = SC[6];
    wire flag_i1       = SC[7];

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
    wire [4:0] micro_mov_src_sec = micro_op[16:12];
    wire [4:0] micro_mov_dst_sec = micro_op[21:17];

    wire microinstruction_done = micro_op[10];
    wire microinstruction_nearly_done = micro_op[11];

    wire [4:0] micro_bus_reg = micro_op[16:12];
    wire [4:0] micro_bus_add = micro_op[21:17];
    wire micro_bus_op = micro_op[22];

    wire [4:0] micro_alu_op = micro_op[27:23];
    wire micro_alu_size = micro_op[28];

    wire [4:0] micro_jmp_condition = micro_op[16:12];
    wire [15:0] jump_dest = top_address +
        (16'd1 << (imm_size | (extended_opcode[9:8] != 0))) +
        (imm_size? imm: {8'd0, imm[7:0]});

    wire [2:0] micro_op_type = micro_op[31:29];

    reg [3:0] microprogram_counter;
    reg [8:0] microaddress;

    task map_microinstruction_register(input [4:0] reg_id, output logic [15:0] register, output logic not_implemented_error);
        not_implemented_error = 0;
        case(reg_id)
            MICRO_MOV_NONE:
                register = 0;

            MICRO_MOV_IMM:
                register = s1c88.imm;

            MICRO_MOV_IMML:
                register = {8'd0, s1c88.imm_low};

            MICRO_MOV_IMMH:
                register = {8'd0, s1c88.imm_high};

            MICRO_MOV_A:
                register = {8'd0, s1c88.A};

            MICRO_MOV_B:
                register = {8'd0, s1c88.B};

            MICRO_MOV_BA:
                register = s1c88.BA;

            MICRO_MOV_IX:
                register = s1c88.IX;

            MICRO_MOV_IY:
                register = s1c88.IY;

            MICRO_MOV_ALU_A:
                register = s1c88.alu_A;

            MICRO_MOV_ALU_B:
                register = s1c88.alu_B;

            MICRO_MOV_ALU_R:
                register = s1c88.alu_R;

            MICRO_MOV_H:
                register = {8'd0, s1c88.HL[15:8]};

            MICRO_MOV_L:
                register = {8'd0, s1c88.HL[7:0]};

            MICRO_MOV_HL:
                register = s1c88.HL;

            MICRO_MOV_SP:
                register = s1c88.SP;

            MICRO_MOV_SC:
                register = {8'd0, s1c88.SC};

            MICRO_MOV_BR:
                register = {8'd0, s1c88.BR};

            MICRO_MOV_PC:
                register = s1c88.PC;

            MICRO_MOV_TA1:
                register = s1c88.top_address + 16'd1;

            MICRO_MOV_TA2:
                register = s1c88.top_address + 16'd2;

            MICRO_MOV_NB:
                register = {8'd0, s1c88.NB};

            MICRO_MOV_CB:
                register = {8'd0, s1c88.CB};

            MICRO_MOV_EP:
                register = {8'd0, s1c88.EP};

            MICRO_MOV_XP:
                register = {8'd0, s1c88.XP};

            MICRO_MOV_YP:
                register = {8'd0, s1c88.YP};

            default:
            begin
                not_implemented_error = 1;
                register = 0;
            end
        endcase
    endtask

    reg [15:0] src_reg;
    reg [15:0] src_reg_sec;
    reg not_implemented_mov_src_error;
    reg not_implemented_mov_src_sec_error;
    always_comb
    begin
        map_microinstruction_register(micro_mov_src, src_reg, not_implemented_mov_src_error);
        map_microinstruction_register(micro_mov_src_sec, src_reg_sec, not_implemented_mov_src_sec_error);
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
    reg [15:0] top_address;

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

                MICRO_ALU_OP_OR:
                    alu_op <= ALUOP_OR;

                MICRO_ALU_OP_XOR:
                    alu_op <= ALUOP_XOR;

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
                    alu_op <= ALUOP_ADD;

            endcase
        end
    end


    reg not_implemented_write_error;
    task write_data_to_register(input [4:0] reg_id, input [15:0] data);
        case(reg_id)
            MICRO_MOV_IX:
                IX <= data;

            MICRO_MOV_IY:
                IY <= data;

            MICRO_MOV_EP:
                EP <= data[7:0];

            MICRO_MOV_XP:
                XP <= data[7:0];

            MICRO_MOV_YP:
                YP <= data[7:0];

            MICRO_MOV_BR:
                BR <= data[7:0];

            MICRO_MOV_SC:
                SC <= data[7:0];

            MICRO_MOV_SP:
                SP <= data;

            MICRO_MOV_H:
                HL[7:0]  <= data[7:0];

            MICRO_MOV_L:
                HL[15:8] <= data[7:0];

            MICRO_MOV_HL:
                HL <= data;

            MICRO_MOV_PCL:
                PC[7:0] <= data[7:0];

            MICRO_MOV_PCH:
                PC[15:8] <= data[7:0];

            MICRO_MOV_CB:
                CB <= data[7:0];

            MICRO_MOV_A:
                BA[7:0] <= data[7:0];

            MICRO_MOV_B:
                BA[15:8] <= data[7:0];

            MICRO_MOV_BA:
                BA <= data;

            MICRO_MOV_ALU_A:
                alu_A <= data;

            MICRO_MOV_ALU_B:
                alu_B <= data;

            default:
            begin
                if(reg_id != MICRO_MOV_NONE && reg_id != MICRO_MOV_PC)
                    not_implemented_write_error <= 1;
            end
        endcase
    endtask

    reg jump_condition_true;
    always_comb
    begin
        jump_condition_true = 0;
        case(micro_jmp_condition)
            // Unconditional jump
            MICRO_COND_NONE:
            begin
                jump_condition_true = 1;
            end
            MICRO_COND_LESS, MICRO_COND_GREATER:
            begin
            end
            MICRO_COND_LESS_EQUAL, MICRO_COND_GREATER_EQUAL:
            begin
            end
            MICRO_COND_OVERFLOW, MICRO_COND_NON_OVERFLOW:
            begin
            end
            MICRO_COND_MINUS, MICRO_COND_PLUS:
            begin
                if(flag_negative == micro_jmp_condition[0])
                    jump_condition_true = 1;
            end
            MICRO_COND_CARRY, MICRO_COND_NON_CARRY:
            begin
                if(flag_carry == micro_jmp_condition[0])
                    jump_condition_true = 1;
            end
            MICRO_COND_ZERO, MICRO_COND_NON_ZERO:
            begin
                if(flag_zero == micro_jmp_condition[0])
                    jump_condition_true = 1;
            end
            MICRO_COND_F0_SET, MICRO_COND_F0_RST:
            begin
            end
            MICRO_COND_F1_SET, MICRO_COND_F1_RST:
            begin
            end
            MICRO_COND_F2_SET, MICRO_COND_F2_RST:
            begin
            end
            MICRO_COND_F3_SET, MICRO_COND_F3_RST:
            begin
            end
            MICRO_COND_B_IS_ZERO:
            begin
            end
            default:
            begin
            end
        endcase
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
            top_address          <= 0;
            not_implemented_write_error <= 0;
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
                not_implemented_write_error <= 0;

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
                    top_address <= PC;
                end
            end
            else if(pl == 1)
            begin
                address_out <= {9'd0, PC[14:0]};

                if(fetch_opcode)
                begin
                    PC <= PC + 1;
                    address_out <= {9'd0, PC[14:0] + 15'd1};
                end

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
                state <= STATE_EXC_PROCESS;

                if(pl == 0)
                begin
                end
                else
                begin
                    exception_process_step <= exception_process_step + 1;

                    if(exception_process_step == 1)
                    begin
                        address_out <= 0;
                    end
                    else if(exception_process_step == 2)
                    begin
                        PC[7:0]     <= data_in;
                        address_out <= 1;
                        iack        <= 0;
                        exception   <= EXCEPTION_TYPE_NONE;
                    end
                    else if(exception_process_step == 3)
                    begin
                        PC[15:8]     <= data_in;
                        address_out  <= {9'd0, data_in[6:0], PC[7:0]};
                        fetch_opcode <= 1;
                        state        <= next_state;
                    end
                end
            end
            else if(state == STATE_OPEXT_READ)
            begin
                if(pl == 0)
                begin
                    opext <= data_in;
                end
                else
                begin
                    PC <= PC + 1;
                    address_out <= {9'd0, PC[14:0] + 15'd1};
                end
            end
            else if(state == STATE_IMM_LOW_READ || state == STATE_IMM_HIGH_READ)
            begin
                if(pl == 1)
                begin
                    PC <= PC + 1;
                    address_out <= {9'd0, PC[14:0] + 15'd1};
                end
            end
            else if(state == STATE_EXECUTE)
            begin
                if(pl == 1)
                begin
                    if(!fetch_opcode)
                    begin
                        state <= STATE_EXECUTE;
                        if(microinstruction_done)
                            fetch_opcode <= 1;

                        if(micro_mov_dst == MICRO_MOV_PC)
                        begin
                            PC <= src_reg;
                            address_out <= {9'b0, src_reg[14:0]};
                        end

                        if(micro_op_type == MICRO_TYPE_JMP)
                        begin
                            // @todo: Do we need to move the NB/CB writing to
                            // pl == 0?
                            if(jump_condition_true)
                            begin
                                PC          <= jump_dest;
                                NB          <= CB;
                                address_out <= {9'b0, jump_dest[14:0]};
                            end
                            else CB <= NB;
                        end
                    end
                end
                else
                begin
                    if(micro_op_type == MICRO_TYPE_BUS && micro_bus_op == MICRO_BUS_MEM_READ)
                    begin
                        write_data_to_register(micro_bus_reg, {8'd0, data_in});
                    end
                    else if(micro_op_type == MICRO_TYPE_MISC)
                    begin
                        write_data_to_register(micro_mov_dst_sec, src_reg_sec);
                    end
                    write_data_to_register(micro_mov_dst, src_reg);
                end
            end

            if(micro_op_type == MICRO_TYPE_BUS && pl == 1)
            begin
                if((state == STATE_EXECUTE && !microinstruction_done) || (next_state == STATE_EXECUTE))
                begin
                // Don't do any bus ops on the last microinstruction
                // step.
                    if(micro_bus_op == MICRO_BUS_MEM_WRITE)
                        bus_status <= BUS_COMMAND_MEM_WRITE;

                    case(micro_bus_add)
                        MICRO_ADD_HL:
                        begin
                            address_out <= {8'b0, HL};
                        end

                        MICRO_ADD_HL1:
                        begin
                            address_out <= {8'b0, HL+16'd1};
                        end

                        MICRO_ADD_HH_LL:
                        begin
                            address_out <= {8'b0, imm};
                        end

                        MICRO_ADD_HH_LL1:
                        begin
                            address_out <= {8'b0, imm+16'd1};
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

                        // @todo: set error flag.
                        default:
                        begin
                        end
                    endcase
                end
            end
                
        end
    end

    reg not_implemented_data_out_error;
    always_ff @ (posedge clk, posedge reset)
    begin
        if(reset)
        begin
            data_out      <= ~0;
            read          <= 0;
            pk            <= 0;
            microaddress  <= 0;
            microprogram_counter <= 0;
            not_implemented_data_out_error <= 0;
        end
        else if(reset_counter >= 2)
        begin
            pk <= ~pk;
            read <= 0;
            not_implemented_data_out_error <= 0;

            if(fetch_opcode)
            begin
                if(pk == 0)
                begin
                    read <= 1;
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
                    end
                end

                STATE_OPEXT_READ:
                begin
                    if(pk == 0)
                    begin
                        read <= 1;
                    end
                end

                STATE_IMM_LOW_READ:
                begin
                    if(pk == 0)
                    begin
                        read <= 1;
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
                                    MICRO_MOV_A:
                                    begin
                                        data_out <= BA[7:0];
                                    end
                                    MICRO_MOV_B:
                                    begin
                                        data_out <= BA[15:8];
                                    end
                                    MICRO_MOV_IXL:
                                    begin
                                        data_out <= IX[7:0];
                                    end
                                    MICRO_MOV_IXH:
                                    begin
                                        data_out <= IX[15:8];
                                    end
                                    MICRO_MOV_IYL:
                                    begin
                                        data_out <= IY[7:0];
                                    end
                                    MICRO_MOV_IYH:
                                    begin
                                        data_out <= IY[15:8];
                                    end
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
                                    MICRO_MOV_PCL:
                                    begin
                                        data_out <= PC[7:0];
                                    end
                                    MICRO_MOV_PCH:
                                    begin
                                        data_out <= PC[15:8];
                                    end
                                    MICRO_MOV_CB:
                                    begin
                                        data_out <= CB;
                                    end

                                    default:
                                    begin
                                        not_implemented_data_out_error <= 1;
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
