
enum [2:0]
{
    BUS_COMMAND_IDLE      = 3'd0,
    BUS_COMMAND_MEM_READ  = 3'd1,
    BUS_COMMAND_MEM_WRITE = 3'd2,
    BUS_COMMAND_IO_READ   = 3'd3,
    BUS_COMMAND_IO_WRITE  = 3'd4
} BusCommand;

module execution_unit
(
    input clk,
    input reset,

    // Prefetch queue
    input [7:0] prefetch_data,
    input queue_empty,
    output queue_pop,
    output reg queue_suspend,
    output reg queue_flush,

    // Program counter
    // The PC is a 16-bit binary counter that holds the offset
    // information of the memory address of the program that the
    // execution unit (EXU) is about to execute.
    output reg [15:0] PC,

    // Segment register input and output
    input [15:0] segment_registers[0:3],
    output [15:0] sregfile_write_data,
    output [1:0] sregfile_write_id,
    output sregfile_we,

    // Execution status
    output instruction_nearly_done,

    // Bus
    output reg [2:0]  bus_command,
    output reg [19:0] bus_address,
    // @todo: Should we just assign this to mov_dst_size ?
    output reg bus_upper_byte_enable,
    output reg [15:0] data_out,

    input [15:0] data_in,
    input bus_command_done
);

    localparam [2:0]
        STATE_OPCODE_READ    = 3'd0,
        STATE_MODRM_READ     = 3'd1,
        STATE_DISP_LOW_READ  = 3'd2,
        STATE_DISP_HIGH_READ = 3'd3,
        STATE_IMM_LOW_READ   = 3'd4,
        STATE_IMM_HIGH_READ  = 3'd5,
        STATE_EXECUTE        = 3'd6;

    localparam [3:0]
        READ_SRC_REG   = 4'd0,
        READ_SRC_SREG  = 4'd1,
        READ_SRC_PC    = 4'd2,
        READ_SRC_IMM   = 4'd3,
        READ_SRC_DISP  = 4'd4,
        READ_SRC_MEM   = 4'd5,
        READ_SRC_ALU   = 4'd6,
        READ_SRC_TMP   = 4'd7,
        READ_SRC_LATCH = 4'd8,
        READ_SRC_ONES  = 4'd9,
        READ_SRC_ZERO  = 4'd10;

    //localparam [2:0]
    //    LJUMP_COND_UNC = 3'd0,
    //        ...

    reg [7:0] opcode;
    reg [7:0] modrm;
    reg [15:0] imm;
    reg [15:0] disp;
    reg [15:0] error;
    reg [15:0] cerror = 0;

    wire has_prefix;
    wire need_modrm;
    wire need_disp;
    wire need_imm;
    wire imm_size;
    wire disp_size;

    // Effective address registers
    wire [3:0] ea_base_reg;
    wire [3:0] ea_index_reg;
    wire [1:0] ea_segment_reg;

    wire [3:0] src_operand;
    wire [3:0] dst_operand;

    wire byte_word_field;

    reg [2:0] state;

    always_latch
    begin
        // @todo: check prefix.
        if(state == STATE_OPCODE_READ)         opcode     = prefetch_data;
        else if(state == STATE_MODRM_READ)     modrm      = prefetch_data;
        else if(state == STATE_DISP_LOW_READ)  disp[7:0]  = prefetch_data;
        else if(state == STATE_DISP_HIGH_READ) disp[15:8] = prefetch_data;
        else if(state == STATE_IMM_LOW_READ)   imm[7:0]   = prefetch_data;
        else if(state == STATE_IMM_HIGH_READ)  imm[15:8]  = prefetch_data;
    end

    // It also makes it easier at initialization, as the opcode takes the
    // value in prefetch_data, at least if it's not empty.

    // @todo: Perhaps we should have the decoder set the appropriate 'factors'
    // value for the physical address calculation.
    decode decode_inst
    (
        .opcode,
        .modrm,

        .need_modrm,

        .need_disp,
        .disp_size,

        .need_imm,
        .imm_size,

        .src(src_operand),
        .dst(dst_operand),

        .byte_word_field(byte_word_field)
    );


    wire [1:0] mod  = modrm[7:6];
    wire [2:0] regm = modrm[5:3];
    wire [2:0] rm   = modrm[2:0];

    // @todo: In principle, we should be able to overlap execution with next
    // opcode read if the last microcode is not a read/write operation.
    // Perhaps we can change state_opcode_read to being a separate wire
    // opcode_read which can be turned on if the instruction is nearly done or
    // done.

    wire [2:0] next_state =
        (state == STATE_OPCODE_READ) ?
            (need_modrm  ? STATE_MODRM_READ:
            (need_disp   ? STATE_DISP_LOW_READ:
            (need_imm    ? STATE_IMM_LOW_READ:
                           STATE_EXECUTE))):

        (state == STATE_MODRM_READ) ?
            (need_disp   ? STATE_DISP_LOW_READ:
            (need_imm    ? STATE_IMM_LOW_READ:
                           STATE_EXECUTE)):

        (state == STATE_DISP_LOW_READ) ?
            (disp_size   ? STATE_DISP_HIGH_READ:
            (need_imm    ? STATE_IMM_LOW_READ:
                           STATE_EXECUTE)):

        (state == STATE_DISP_HIGH_READ) ?
            (need_imm    ? STATE_IMM_LOW_READ:
                           STATE_EXECUTE):

        (state == STATE_IMM_LOW_READ) ?
            (imm_size    ? STATE_IMM_HIGH_READ:
                           STATE_EXECUTE):

        (state == STATE_IMM_HIGH_READ) ?
                           STATE_EXECUTE:
                           STATE_OPCODE_READ;

    // @info: The opcode is translated directly to a rom address. This can be done by
    //creating a rom of size 256 indexed by the opcode, where the value is
    //equal to the microcode rom address.

    reg [8:0] translation_rom[0:255];
    reg [8:0] jump_table[0:15];
    reg [26:0] rom[0:511];

    localparam [2:0]
        MICRO_TYPE_MISC = 3'b100,
        MICRO_TYPE_BUS  = 3'b110,
        MICRO_TYPE_JMP  = 3'b101;

    localparam [1:0]
        MICRO_TYPE_ALU  = 2'b01,
        MICRO_TYPE_SJMP = 2'b00;

    localparam [4:0]
        MICRO_MOV_NONE = 5'h00,
        // register specified by r field of modrm.
        MICRO_MOV_R    = 5'h01,
        // register or memory specified by rm field of modrm.
        MICRO_MOV_RM   = 5'h02,

        // disp value specified by opcode bytes. Cannot be destination.
        MICRO_MOV_DISP = 5'h03,

        // imm value specified by opcode bytes. Cannot be destination.
        MICRO_MOV_IMM   = 5'h04,
        MICRO_MOV_ADD   = 5'h04,

        MICRO_MOV_ALU_A = 5'h05, // dst
        MICRO_MOV_ALU_R = 5'h05, // src

        MICRO_MOV_ZERO  = 5'h06, // dst
        MICRO_MOV_ONES  = 5'h07, // dst
        MICRO_MOV_TMP   = 5'h09, // src/dst

        //MICRO_MOV_TMPW  = 5'h09, // src/dst
        //MICRO_MOV_TMPL  = 5'h0a, // src/dst
        //MICRO_MOV_TMPH  = 5'h0b, // src/dst

        // all registers:
        MICRO_MOV_AL    = 5'h08,
        MICRO_MOV_AH    = 5'h0c,

        MICRO_MOV_AW    = 5'h10,
        MICRO_MOV_CW    = 5'h11,
        MICRO_MOV_DW    = 5'h12,
        MICRO_MOV_BW    = 5'h13,

        MICRO_MOV_SP    = 5'h14,
        MICRO_MOV_BP    = 5'h15,
        MICRO_MOV_IX    = 5'h16,
        MICRO_MOV_IY    = 5'h17,

        MICRO_MOV_DS1   = 5'h18,
        MICRO_MOV_PS    = 5'h19,
        MICRO_MOV_SS    = 5'h1a,
        MICRO_MOV_DS0   = 5'h1b,

        MICRO_MOV_PC    = 5'h1c;

    localparam [3:0]
        MICRO_MISC_OP_A_NONE  = 4'h0,
        MICRO_MISC_OP_A_FLUSH = 4'h1;

    localparam [2:0]
        MICRO_MISC_OP_B_NONE  = 3'h0,
        MICRO_MISC_OP_B_SUSP  = 3'h1;

    localparam [1:0]
        MICRO_BUS_MEM_READ  = 2'h0,
        MICRO_BUS_MEM_WRITE = 2'h1,
        MICRO_BUS_IO_READ   = 2'h2,
        MICRO_BUS_IO_WRITE  = 2'h3;

    localparam [1:0]
        MICRO_BUS_SEG_ZERO = 2'b00,
        MICRO_BUS_SEG_SS   = 2'b01,
        MICRO_BUS_SEG_DS0  = 2'b10,
        MICRO_BUS_SEG_DS1  = 2'b11;

    localparam [2:0]
        MICRO_BUS_IND_ZERO = 3'd0,
        MICRO_BUS_IND_INC1 = 3'd1,
        MICRO_BUS_IND_INC2 = 3'd2,
        MICRO_BUS_IND_DEC1 = 3'd3,
        MICRO_BUS_IND_DEC2 = 3'd4,
        MICRO_BUS_IND_BL   = 3'd5;

    localparam
        MICRO_ALU_IGNORE_RESULT = 1'b0,
        MICRO_ALU_USE_RESULT    = 1'b1;

    localparam
        MICRO_JMP_XC = 3'd0,
        MICRO_JMP_UC = 3'd1,
        MICRO_JMP_NZ = 3'd2;

    localparam
        MICRO_SJMP_NREP = 3'd0;

    // @note:
    // Alu ops used by 8086 microcode.
    //
    // 'XI', 'AND', 'ADD', 'SUBT', 'INC', 'INC2', 'DEC', 'DEC2', 'NEG', 'LRCY', 'RRCY', 'XZC', 'COM1', 'PASS'
    //
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

        // @note: Still need these, I think:
        //     MICRO_MOV_PSW  = 5'h18,
        //     MICRO_MOV_EA   = 5'h19,
        //     MICRO_MOV_ALUR = 5'h1a,
        //     MICRO_MOV_ALUX = 5'h1b,
        //     MICRO_MOV_ALUY = 5'h1c,
        //
        // The 8086 microcode seems to even introduce some temporary registers
        // and does not explicitly use the upper and lower half of the
        // registers b, c, and d. In total, 26 values for src and 26 values
        // for dst are used. The combined src and dst refer to a combined 33
        // unique values, so a common coding for both is not possible with 5
        // bits. I think it's best to encode the common ones, and for the
        // others, introduce combination values, e.g. MICRO_MOV_ES_OR_SIGMA.
        // This brings the number of unique values to about 25. The move src
        // never seems to refer to bw, and bp, though. If I add them to the
        // common registers, it would increase them to 21. I could do the same
        // with the 3 remaining segment registers, making the total of 24, and
        // 5 dst and 4  src registers. With a total of 29 registers, we should
        // be then fine. That's 2 short of the 31 total.
        //
        // Note that the 8086 microcode also includes references to microcode
        // address registers, namely an address register, the microprogram
        // count register, and the subroutine register. There is also a value
        // for read byte from prefetch queue, which we'll not use in our design.
        //
        // It's also important to note that I don't know if the v30mz uses any
        // of the b, c, and d lower and upper registers.

    // Pop at any time that we are not executing and the queue is not empty.
    assign queue_pop = !reset && (state < STATE_EXECUTE) && !queue_empty;

    initial
    begin
        // micro_op:
        // -----------------------
        // 0:4; source
        // 5:9; destination
        // 10; next_last (nx)
        // 11; last (nl)
        // 12:21; type, a, b

        for (int i = 0; i < 512; i++)
            rom[i] = 0;

        //        type,             b,                    b                            nl/nx, destination,    source
        rom[0]  = {MICRO_TYPE_MISC, 5'd0, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,  2'b10, MICRO_MOV_NONE, MICRO_MOV_NONE}; // NOP

        rom[1]  = {MICRO_TYPE_MISC, 5'd0, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,  2'b10, MICRO_MOV_R,    MICRO_MOV_RM};
        rom[2]  = {MICRO_TYPE_MISC, 5'd0, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,  2'b10, MICRO_MOV_RM,   MICRO_MOV_R};
        rom[3]  = {MICRO_TYPE_MISC, 5'd0, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,  2'b10, MICRO_MOV_RM,   MICRO_MOV_IMM};

        // BR far_label
        rom[4]  = {MICRO_TYPE_MISC, 5'd0, MICRO_MISC_OP_B_SUSP, MICRO_MISC_OP_A_NONE,  2'b00, MICRO_MOV_PS,   MICRO_MOV_IMM};
        rom[5]  = {MICRO_TYPE_MISC, 5'd0, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_FLUSH, 2'b10, MICRO_MOV_PC,   MICRO_MOV_DISP};

        // OUT acc -> imm8
        // @info: Bus: ttt.uussbb (t = type, b = bus operation s = segment)
        rom[6]  = {MICRO_TYPE_BUS, 5'd0, MICRO_BUS_IND_ZERO, MICRO_BUS_SEG_ZERO, MICRO_BUS_IO_WRITE, 2'b10, MICRO_MOV_AW, MICRO_MOV_IMM};

        // IN imm8 <- acc
        rom[8]  = {MICRO_TYPE_BUS, 5'd0, MICRO_BUS_IND_ZERO, MICRO_BUS_SEG_ZERO, MICRO_BUS_IO_READ, 2'b10, MICRO_MOV_AW, MICRO_MOV_IMM};

        // @info: ALU: tt?????u??aaaaa (t = type, u = use alu result, a = alu op)
        // @note: If MICRO_ALU_USE_RESULT but src is memory, then don't write
        // result back this step but instead run the next microinstruction.
        rom[10] = {MICRO_TYPE_ALU, 5'd0, MICRO_ALU_USE_RESULT, 2'd0, MICRO_ALU_OP_XI,  2'b10, MICRO_MOV_RM, MICRO_MOV_ONES};
        rom[11] = {MICRO_TYPE_MISC, 5'd0, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,  2'b10, MICRO_MOV_RM, MICRO_MOV_ALU_R};

        // @info: Long jump: ttt?????cccdddd (t = type, c = jump condition, d = jump
        // destination)
        rom[12] = {MICRO_TYPE_JMP, 5'd0, MICRO_JMP_XC, 4'h0,                          2'b10, MICRO_MOV_NONE, MICRO_MOV_NONE};

        // @note: Can make this 2 microinstructions, but v30mz runs in 3.
        rom[13] = {MICRO_TYPE_MISC, 5'd0, MICRO_MISC_OP_B_SUSP, MICRO_MISC_OP_A_NONE,  2'b00, MICRO_MOV_NONE, MICRO_MOV_NONE};
        rom[14] = {MICRO_TYPE_ALU, 5'd0, MICRO_ALU_IGNORE_RESULT, 2'd0, MICRO_ALU_OP_ADD, 2'b01, MICRO_MOV_PC, MICRO_MOV_DISP};
        rom[15] = {MICRO_TYPE_MISC, 5'd0, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_FLUSH, 2'b10, MICRO_MOV_PC, MICRO_MOV_ALU_R};

        // ALU ACC IMM
        rom[16] = {MICRO_TYPE_ALU, 5'd0, MICRO_ALU_USE_RESULT, 2'd0, MICRO_ALU_OP_XI,  2'b10, MICRO_MOV_AW, MICRO_MOV_IMM};

        // INC RM
        rom[17] = {MICRO_TYPE_ALU, 5'd0, MICRO_ALU_USE_RESULT, 2'd0, MICRO_ALU_OP_XI,  2'b10, MICRO_MOV_RM, MICRO_MOV_ONES};
        rom[18] = {MICRO_TYPE_MISC, 5'd0, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,  2'b10, MICRO_MOV_RM, MICRO_MOV_ALU_R};

        rom[19] = {MICRO_TYPE_ALU, 5'd0, MICRO_ALU_USE_RESULT, 2'd0, MICRO_ALU_OP_XI,  2'b10, MICRO_MOV_RM, MICRO_MOV_IMM};
        rom[20] = {MICRO_TYPE_MISC, 5'd0, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,  2'b10, MICRO_MOV_RM, MICRO_MOV_ALU_R};

        // BR near/short-label
        rom[21] = {MICRO_TYPE_JMP, 5'd0, MICRO_JMP_UC, 4'h0,                          2'b10, MICRO_MOV_NONE, MICRO_MOV_NONE};

        rom[22] = {MICRO_TYPE_JMP, 5'd0, MICRO_JMP_UC, 4'h0,                          2'b10, MICRO_MOV_NONE, MICRO_MOV_NONE};

        rom[23] = {MICRO_TYPE_ALU, 5'd0, MICRO_ALU_USE_RESULT, 2'd0, MICRO_ALU_OP_XI,  2'b10, MICRO_MOV_R, MICRO_MOV_RM};
        rom[24] = {MICRO_TYPE_ALU, 5'd0, MICRO_ALU_USE_RESULT, 2'd0, MICRO_ALU_OP_XI,  2'b10, MICRO_MOV_RM, MICRO_MOV_R};

        // CALL far-proc
        // @todo: convert these bus calls to the new convention.
        rom[25] = {MICRO_TYPE_BUS, -5'sd2, MICRO_BUS_IND_DEC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_WRITE, 2'b00, MICRO_MOV_PS, MICRO_MOV_SP};
        rom[26] = {MICRO_TYPE_MISC, 5'd0, MICRO_MISC_OP_B_SUSP, MICRO_MISC_OP_A_NONE,   2'b00, MICRO_MOV_PS, MICRO_MOV_IMM};
        rom[27] = {MICRO_TYPE_BUS, -5'sd2, MICRO_BUS_IND_DEC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_WRITE, 2'b00, MICRO_MOV_PC, MICRO_MOV_SP};
        rom[28] = {MICRO_TYPE_MISC, 5'd0, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_FLUSH,  2'b10, MICRO_MOV_PC, MICRO_MOV_DISP};

        // Just do a memory read request, and we'll take care of using the
        // data in data_in next step.
        // @todo: Is this possible or do we need e.g. latch the data to reg_tmp?
        rom[29] = {MICRO_TYPE_MISC, 5'd0, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,  2'b00, MICRO_MOV_NONE, MICRO_MOV_RM};
        rom[30] = {MICRO_TYPE_BUS, -5'sd2, MICRO_BUS_IND_DEC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_WRITE, 2'b10, MICRO_MOV_RM, MICRO_MOV_SP};

        //rom[30] = {MICRO_TYPE_MISC, 5'd0, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,  2'b00, MICRO_MOV_NONE, MICRO_MOV_RM};
        rom[32] = {MICRO_TYPE_BUS, 5'sd0, MICRO_BUS_IND_INC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_READ, 2'b10, MICRO_MOV_RM, MICRO_MOV_SP};

        // To return from call outside segment
        // PC ← (SP + 1, SP)
        // PS ← (SP + 3, SP + 2)
        // SP ← SP + 4
        rom[33] = {MICRO_TYPE_MISC, 5'd0, MICRO_MISC_OP_B_SUSP, MICRO_MISC_OP_A_NONE,  2'b00, MICRO_MOV_NONE, MICRO_MOV_NONE};
        rom[34] = {MICRO_TYPE_BUS, 5'sd0, MICRO_BUS_IND_INC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_READ, 2'b00, MICRO_MOV_PC, MICRO_MOV_SP};
        rom[35] = {MICRO_TYPE_BUS, 5'sd0, MICRO_BUS_IND_INC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_READ, 2'b00, MICRO_MOV_PS, MICRO_MOV_SP};
        rom[36] = {MICRO_TYPE_MISC, 5'd0, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_FLUSH,  2'b10, MICRO_MOV_NONE, MICRO_MOV_NONE};

        rom[37] = {MICRO_TYPE_ALU, 5'd0, MICRO_ALU_USE_RESULT, 2'd0, MICRO_ALU_OP_DEC, 2'b00, MICRO_MOV_CW, MICRO_MOV_ONES};
        rom[38] = {MICRO_TYPE_JMP, 5'd0, MICRO_JMP_NZ, 4'h0,                           2'b10, MICRO_MOV_NONE, MICRO_MOV_NONE};

        rom[39] = {MICRO_TYPE_ALU, 5'd0, MICRO_ALU_IGNORE_RESULT, 2'd0, MICRO_ALU_OP_AND, 2'b10, MICRO_MOV_R, MICRO_MOV_RM};
        rom[40] = {MICRO_TYPE_ALU, 5'd0, MICRO_ALU_IGNORE_RESULT, 2'd0, MICRO_ALU_OP_AND, 2'b10, MICRO_MOV_RM, MICRO_MOV_IMM};
        rom[41] = {MICRO_TYPE_ALU, 5'd0, MICRO_ALU_IGNORE_RESULT, 2'd0, MICRO_ALU_OP_AND, 2'b10, MICRO_MOV_AW, MICRO_MOV_IMM};

        // PUSH R
        rom[42] = {MICRO_TYPE_MISC, 5'd0, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,  2'b00, MICRO_MOV_TMP, MICRO_MOV_SP};
        rom[43] = {MICRO_TYPE_BUS, 5'sd0, MICRO_BUS_IND_DEC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_WRITE, 2'b00, MICRO_MOV_AW, MICRO_MOV_SP};
        rom[44] = {MICRO_TYPE_BUS, 5'sd0, MICRO_BUS_IND_DEC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_WRITE, 2'b00, MICRO_MOV_CW, MICRO_MOV_SP};
        rom[45] = {MICRO_TYPE_BUS, 5'sd0, MICRO_BUS_IND_DEC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_WRITE, 2'b00, MICRO_MOV_DW, MICRO_MOV_SP};
        rom[46] = {MICRO_TYPE_BUS, 5'sd0, MICRO_BUS_IND_DEC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_WRITE, 2'b00, MICRO_MOV_BW, MICRO_MOV_SP};
        rom[47] = {MICRO_TYPE_BUS, 5'sd0, MICRO_BUS_IND_DEC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_WRITE, 2'b00, MICRO_MOV_TMP, MICRO_MOV_SP};
        rom[48] = {MICRO_TYPE_BUS, 5'sd0, MICRO_BUS_IND_DEC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_WRITE, 2'b00, MICRO_MOV_BP, MICRO_MOV_SP};
        rom[49] = {MICRO_TYPE_BUS, 5'sd0, MICRO_BUS_IND_DEC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_WRITE, 2'b01, MICRO_MOV_IX, MICRO_MOV_SP};
        rom[50] = {MICRO_TYPE_BUS, 5'sd0, MICRO_BUS_IND_DEC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_WRITE, 2'b10, MICRO_MOV_IY, MICRO_MOV_SP};

        // short jump (tt?????cccddddd)
        // @note: We are using a short jump to jump over the CW decrement when
        // the repeat flag is not set. Alternatively, since we have several
        // unused bits on ALU, we could use 1 bit to skip the instruction if
        // repeat is not set. When repeat is active, it saves us
        // 1 microinstruction.
        // @note: Probably need to add an instruction of interrupt acknowledge
        // at some point.
        rom[51] = {MICRO_TYPE_SJMP, 5'd0, MICRO_SJMP_NREP, 5'sd2, 2'b00, MICRO_MOV_NONE, MICRO_MOV_NONE};
        rom[52] = {MICRO_TYPE_ALU, 5'd0, MICRO_ALU_USE_RESULT, 2'd0, MICRO_ALU_OP_DEC, 2'b00, MICRO_MOV_CW, MICRO_MOV_ONES};
        rom[53] = {MICRO_TYPE_BUS, 5'sd0, MICRO_BUS_IND_BL, MICRO_BUS_SEG_DS0, MICRO_BUS_MEM_READ,  2'b00, MICRO_MOV_TMP, MICRO_MOV_IX};
        rom[54] = {MICRO_TYPE_BUS, 5'sd0, MICRO_BUS_IND_BL, MICRO_BUS_SEG_DS1, MICRO_BUS_MEM_WRITE, 2'b10, MICRO_MOV_TMP, MICRO_MOV_IY};

        // POP R
        rom[55] = {MICRO_TYPE_BUS, 5'sd0, MICRO_BUS_IND_INC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_READ, 2'b00, MICRO_MOV_IY, MICRO_MOV_SP};
        rom[56] = {MICRO_TYPE_BUS, 5'sd0, MICRO_BUS_IND_INC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_READ, 2'b00, MICRO_MOV_IX, MICRO_MOV_SP};
        rom[57] = {MICRO_TYPE_BUS, 5'sd0, MICRO_BUS_IND_INC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_READ, 2'b00, MICRO_MOV_BP, MICRO_MOV_SP};
        rom[58] = {MICRO_TYPE_BUS, 5'sd0, MICRO_BUS_IND_INC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_READ, 2'b00, MICRO_MOV_NONE, MICRO_MOV_SP};
        rom[59] = {MICRO_TYPE_BUS, 5'sd0, MICRO_BUS_IND_INC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_READ, 2'b00, MICRO_MOV_BW, MICRO_MOV_SP};
        rom[60] = {MICRO_TYPE_BUS, 5'sd0, MICRO_BUS_IND_INC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_READ, 2'b00, MICRO_MOV_DW, MICRO_MOV_SP};
        rom[61] = {MICRO_TYPE_BUS, 5'sd0, MICRO_BUS_IND_INC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_READ, 2'b01, MICRO_MOV_CW, MICRO_MOV_SP};
        rom[62] = {MICRO_TYPE_BUS, 5'sd0, MICRO_BUS_IND_INC2, MICRO_BUS_SEG_SS, MICRO_BUS_MEM_READ, 2'b10, MICRO_MOV_AW, MICRO_MOV_SP};

        for (int i = 0; i < 256; i++)
            translation_rom[i] = 0;

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1000101, i[0]}] = 9'd1;          // MOV mem -> reg

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1000100, i[0]}] = 9'd2;          // MOV reg -> mem

        for (int j = 0; j < 8; j++)
            for (int i = 0; i < 2; i++)
                translation_rom[{4'b1011, i[0], j[2:0]}] = 9'd3; // MOV imm -> reg

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1100011, i[0]}] = 9'd3;          // MOV imm -> rm

        translation_rom[8'b10001100] = 9'd2;                     // MOV sreg -> rm
        translation_rom[8'b10001110] = 9'd1;                     // MOV rm -> sreg
        translation_rom[8'b11101010] = 9'd4;                     // BR far_label

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1110011, i[0]}] = 9'd6;          // OUT acc -> imm8

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1110010, i[0]}] = 9'd8;          // IN acc -> imm8

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1101000, i[0]}] = 9'd10;         // ROL 1 -> rm

        for (int i = 0; i < 4; i++)
            translation_rom[{6'b001000, i[1:0]}] = 9'd10;        // AND r -> rm

        for (int i = 0; i < 16; i++)
            translation_rom[{2'b00, i[3:1], 2'b10, i[0]}] = 9'd16; // ALU imm -> acc

        for (int i = 0; i < 16; i++)
            translation_rom[{4'b0111, i[3:0]}] = 9'd12;          // BNC

        for (int i = 0; i < 16; i++)
            translation_rom[{4'b0100, i[3:0]}] = 9'd17;          // INC/DEC reg16

        for (int i = 0; i < 4; i++)
            translation_rom[{6'b1000_00, i[1:0]}] = 9'd19;       // ALU imm -> rm (Arithmetic family)

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1100_000, i[0]}] = 9'd19;        // ALU imm -> rm (Shift family)

        for (int i = 0; i < 16; i++)
            translation_rom[{2'b00, i[3:1], 2'b01, i[0]}] = 9'd23; // ALU rm -> r

        for (int i = 0; i < 16; i++)
            translation_rom[{2'b00, i[3:1], 2'b00, i[0]}] = 9'd24; // ALU r  -> rm

        translation_rom[8'b1110_1001] = 9'd21;                   // BR near-label
        translation_rom[8'b1110_1011] = 9'd21;                   // BR short-label

        translation_rom[8'b1001_1010] = 9'd25;                   // CALL far-proc

        for (int i = 0; i < 4; i++)
            translation_rom[{3'b000, i[1:0], 3'b110}] = 9'd30;   // PUSH sreg

        for (int i = 0; i < 8; i++)
            translation_rom[{5'b0101_0, i[2:0]}] = 9'd30;        // PUSH reg16

        for (int i = 0; i < 4; i++)
            translation_rom[{3'b000, i[1:0], 3'b111}] = 9'd32;   // POP sreg

        for (int i = 0; i < 8; i++)
            translation_rom[{5'b0101_1, i[2:0]}] = 9'd32;        // POP reg16

        translation_rom[8'b1100_1011] = 9'd33;                   // RET (segment-external call)

        translation_rom[8'b1110_0010] = 9'd37;                   // DBNZ loop

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1000_010, i[0]}] = 9'd39;        // TEST rm -> r

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1111_011, i[0]}] = 9'd40;        // TEST imm -> rm

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1010_100, i[0]}] = 9'd41;        // TEST imm -> acc

        translation_rom[8'b0110_0000] = 9'd42;                   // PUSH R
        translation_rom[8'b0110_0001] = 9'd55;                   // POP R

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1010_010, i[0]}] = 9'd51;       // MOVBK(B/W)

        for (int i = 0; i < 16; i++)
            jump_table[i] = 9'd0;

        jump_table[0] = 9'd13;

    end

    reg sregfile_we_r;
    assign sregfile_we = sregfile_we_r && (!read_write_wait || bus_command_done);

    reg regfile_we_r;
    wire regfile_we = regfile_we_r && (!read_write_wait || bus_command_done);
    wire [2:0] regfile_write_id;
    wire [15:0] regfile_write_data;

    // We use the secondary write port of the register file for bus microcode
    // index updates.
    reg regfile_we_r_secondary;
    wire regfile_we_secondary = regfile_we_r_secondary && (!read_write_wait || bus_command_done);
    reg [2:0] regfile_write_id_secondary;
    wire [15:0] regfile_write_data_secondary = reg_tmp_bus;

    wire [15:0] registers[0:7];

    // Latched mov info for performing mov on next posedge clk.
    reg [2:0] reg_src;
    reg [2:0] reg_dst;

    // @important: mov_src_size and mov_dst_size should be the same!
    reg mov_src_size;
    reg mov_dst_size;
    reg [3:0] mov_from;

    wire [15:0] mov_data_temp =
         (mov_from == READ_SRC_SREG) ? segment_registers[reg_src[1:0]]:
        ((mov_from == READ_SRC_PC)   ? PC:
        ((mov_from == READ_SRC_ZERO) ? 0:
        ((mov_from == READ_SRC_ONES) ? 1:
        ((mov_from == READ_SRC_MEM)  ? ((mov_src_size == 1) ? data_in: {8'd0, data_in[7:0]}):
        ((mov_from == READ_SRC_IMM)  ? ((mov_src_size == 1) ? imm: {8'd0, imm[7:0]}):
        ((mov_from == READ_SRC_DISP) ? disp_sign_extended:
        ((mov_from == READ_SRC_TMP)  ? ((mov_src_size == 1) ? temp_reg: {8'd0, temp_reg[7:0]}):
        ((mov_src_size == 1)         ? registers[reg_src]:
        ((reg_src[2]   == 0)         ? {8'd0, registers[{1'd0, reg_src[1:0]}][7:0]}:
                                       {8'd0, registers[{1'd0, reg_src[1:0]}][15:8]})))))))));

    //wire [15:0] mov_data_alu =
    //    (mov_from == READ_SRC_TMP)  ? ((mov_src_size == 1) ? reg_tmp: {8'd0, reg_tmp[7:0]}):
    //                                   mov_data_temp;

    //wire [15:0] mov_data_reg_tmp =
    //    (mov_from == READ_SRC_ALU)  ? ((mov_src_size == 1) ? alu_r: {8'd0, alu_r[7:0]}):
    //                                   mov_data_temp;

    // @todo: This is not a very nice way to handle mov_src_size.
    wire [15:0] mov_data =
         (mov_from == READ_SRC_LATCH)  ? ((mov_src_size == 1) ? temp_latch: {8'd0, temp_latch[7:0]}):
        ((mov_from == READ_SRC_ALU)  ? ((mov_src_size == 1) ? alu_r: {8'd0, alu_r[7:0]}):
                                       mov_data_temp);

    assign regfile_write_id = (mov_src_size == 1) ? reg_dst: {1'd0, reg_dst[1:0]};

    wire micro_bus_read  = (micro_op_type == MICRO_TYPE_BUS) && (micro_bus_op[0] == 0);
    wire micro_bus_write = (micro_op_type == MICRO_TYPE_BUS) && (micro_bus_op[0] == 1);
    wire [15:0] regfile_write_data_temp =
         alu_reg_wb           ? alu_r:
        (micro_bus_read       ? data_in: mov_data);

    // @todo: We actually need to take into account both mov_src_size and
    // mov_dst_size. If e.g. mov_src_size = 1 and mov_dst_size = 0, then we
    // have to take the smallest of the two into account when movind data. Of
    // course this means that mov_dst_size needs to be correctly set
    // everywhere.
    assign regfile_write_data =
         (mov_src_size == 1) ? regfile_write_data_temp:
        ((reg_dst[2]   == 0) ? {
                                   registers[regfile_write_id][15:8],
                                   regfile_write_data_temp[7:0]
                               }:
                               {
                                   regfile_write_data_temp[7:0],
                                   registers[regfile_write_id][7:0]
                               });

    assign sregfile_write_id   = reg_dst[1:0];
    assign sregfile_write_data = regfile_write_data_temp;

    //wire micro_bus_ind_update = (micro_op_type == MICRO_TYPE_BUS) && (micro_bus_ind != MICRO_BUS_IND_ZERO);


    wire [15:0] micro_bus_ind_offset =
         (micro_bus_ind == MICRO_BUS_IND_INC1)?  1:
        ((micro_bus_ind == MICRO_BUS_IND_INC2)?  2:
        ((micro_bus_ind == MICRO_BUS_IND_DEC1)? -1:
        ((micro_bus_ind == MICRO_BUS_IND_DEC2)? -2:
                                                 0)));

    // The register file holds the following registers
    //
    // * General purpose registers (AW, BW, CW, DW)
    //   There are four 16-bit registers. These can be not only used
    //   as 16-bit registers, but also accessed as 8-bit registers
    //   (AH, AL, BH, BL, CH, CL, DH, DL) by dividing each register
    //   into the higher 8 bits and the lower 8 bits.
    //
    // * Pointer registers (SP, BP)
    //   The pointer consists of two 16-bit registers (stack pointer
    //   (SP) and base pointer (BP)).
    //
    // * Index registers (IX, IY)
    //   This consists of two 16-bit registers (IX, IY). In a
    //   memory data reference, it is used as an index register to
    //   generate effective addresses (each register can also be
    //   referenced in an instruction).

    register_file register_file_inst
    (
        .clk,
        .reset,
        .we(regfile_we),
        .write_id(regfile_write_id),
        .write_data(regfile_write_data),

        .we_secondary(regfile_we_secondary),
        .write_id_secondary(regfile_write_id_secondary),
        .write_data_secondary(regfile_write_data_secondary),
        .registers
    );

    wire [19:0] physical_address;
    wire [15:0] disp_sign_extended = (disp_size == 1)? disp: {{8{disp[7]}}, disp[7:0]}; // Sign extend
    reg [2:0] segment_override = 0; // High bit = enable/disable override.
    physical_address_calculator pac
    (
        .physical_address(physical_address),
        .registers,
        .segment_registers,
        .segment_override(segment_override),
        .displacement(disp_sign_extended),
        .mod(mod),
        .rm(rm)
    );

    reg [15:0] alu_a, alu_b;
    reg [4:0] alu_op = 0;
    reg alu_size = 0;
    wire [15:0] alu_r;
    wire [5:0] alu_flags;
    reg [5:0] alu_flags_r;
    alu alu_inst
    (
        .alu_op,
        .size(alu_size),
        .A(alu_a), .B(alu_b), .R(alu_r),
        .flags(alu_flags)
    );

    localparam [1:0]
        CTRL_FLAG_MD  = 2'd0, // Mode flag
        CTRL_FLAG_DIR = 2'd1, // Direction flag
        CTRL_FLAG_IE  = 2'd2, // Interrupt enable flag
        CTRL_FLAG_BRK = 2'd3; // Break flag

    reg [3:0] control_flags;

    // @note: This might play a more important role later, e.g. we might have
    // a microinstruction flag telling us if we should we for the read/write
    // before running the next microinstruction.
    reg read_write_wait;
    // @todo: Make this smaller
    reg [3:0] microprogram_counter;
    wire [26:0] micro_op;
    reg [8:0] microaddress;

    wire [4:0] micro_mov_src;
    assign micro_mov_src = micro_op[4:0];

    wire [4:0] micro_mov_dst;
    assign micro_mov_dst =
         (micro_op_type[2:1] == MICRO_TYPE_ALU)? MICRO_MOV_ALU_A:
        ((micro_op_type[2:0] == MICRO_TYPE_BUS)? MICRO_MOV_ADD: micro_op[9:5]);

    assign micro_op = rom[microaddress + {5'd0, microprogram_counter}];

    reg [15:0] temp_reg; // temp register.
    reg [15:0] temp_latch; // temp latch used to set the value of the temp_reg or of other registers.
    reg [15:0] reg_tmp_bus; // register used by bus for address calculation storage.
    reg [15:0] pc_write_data; // temp register which can be used as read source.

    // @note: Also run next microinstruction when we have alu writeback.
    wire alu_mem_wb = (
        (micro_op_type[2:1] == MICRO_TYPE_ALU) &&
        (micro_alu_use == MICRO_ALU_USE_RESULT) &&
        (alu_op != ALUOP_CMP) &&
        ((micro_op[9:5] == MICRO_MOV_RM) && need_modrm && (mod != 2'b11))
    );

    wire alu_reg_wb = (
        (micro_op_type[2:1] == MICRO_TYPE_ALU) &&
        (micro_alu_use == MICRO_ALU_USE_RESULT) &&
        (alu_op != ALUOP_CMP) &&
        (!need_modrm || (mod == 2'b11))
    );

    reg branch_taken = 0;
    assign instruction_nearly_done = micro_op[10];
    wire instruction_maybe_done = (micro_op[11] && !alu_mem_wb && !branch_taken);

    wire [2:0] micro_op_type   = micro_op[26:24];

    wire [3:0] micro_misc_op_a = micro_op[15:12];
    wire [2:0] micro_misc_op_b = micro_op[18:16];
    wire [4:0] micro_misc_op_c = micro_op[23:19];

    wire [1:0] micro_bus_op    = micro_op[13:12];
    wire [1:0] micro_bus_seg   = micro_op[15:14];
    wire [2:0] micro_bus_ind   = micro_op[18:16];
    wire [4:0] micro_bus_disp  = micro_op[23:19];
    wire [19:0] micro_bus_disp_se = {{15{micro_bus_disp[4]}}, micro_bus_disp};

    wire       micro_alu_use   = micro_op[19];
    wire [4:0] micro_alu_op    = micro_op[16:12];

    wire [2:0] micro_jmp_condition   = micro_op[18:16];
    wire [3:0] micro_jmp_destination = micro_op[15:12];

    // short jump (tt?????cccddddd)
    wire [2:0] micro_sjmp_condition = micro_op[19:17];
    wire [4:0] micro_sjmp_offset    = micro_op[16:12];

    //assign queue_flush   = (micro_op_type == 3'b001) && (micro_misc_op_a == MICRO_MISC_OP_A_FLUSH);
    //assign queue_suspend = (micro_op_type == 3'b001) && (micro_misc_op_b == MICRO_MISC_OP_B_SUSP);

    reg [1:0] instruction_step = 0;
    reg instruction_repeat = 0;
    always_latch
    begin
        error <= 0;

        if(bus_command_done)
        begin
            read_write_wait <= 0;
            bus_command     <= BUS_COMMAND_IDLE;
            regfile_we_r    <= 0;
        end

        if(!read_write_wait)
        begin
            regfile_we_r           <= 0;
            regfile_we_r_secondary <= 0;
            sregfile_we_r          <= 0;
        end

        if(reset)
        begin
            read_write_wait        <= 0;
            bus_command            <= BUS_COMMAND_IDLE;
            bus_upper_byte_enable  <= 1;
            regfile_we_r           <= 0;
            regfile_we_r_secondary <= 0;
            sregfile_we_r          <= 0;
        end

        // @todo: I think we forgot the MICRO_MOV_NONE.

        // * Handle move command *
        if(state == STATE_EXECUTE)
        begin
            // @note: For Group 2 instructions we set the microaddress
            // manually.
            if(translation_rom[opcode] == 0 && opcode[7:1] != 7'h7F)
            begin
                case(opcode)
                    8'hAA:
                        error <= `__LINE__;

                    8'hAB: // STMW
                    begin
                        modrm = 8'b00000101;

                        if(instruction_step == 0 && instruction_repeat)
                        begin
                            // @todo: Do I need to do something with the Z-flag?

                            alu_a    <= 1;
                            alu_b    <= registers[1];
                            alu_size <= 1;
                            alu_op   <= ALUOP_DEC;

                            regfile_we_r <= 1;
                            reg_dst      <= 1;
                            mov_from     <= READ_SRC_ALU;
                            mov_src_size <= 1;
                            mov_dst_size <= 1;
                        end
                        else if(instruction_step == 1)
                        begin
                            bus_command     <= BUS_COMMAND_MEM_WRITE;
                            bus_address     <= physical_address;
                            data_out        <= registers[0];
                            read_write_wait <= 1;
                        end
                        // @todo: Check if the second check is superfluous.
                        else if(instruction_step == 2 && bus_command_done)
                        begin
                            reg_dst      <= 7;
                            mov_from     <= READ_SRC_LATCH;
                            mov_src_size <= 1;
                            mov_dst_size <= 1;
                            regfile_we_r <= 1;
                            temp_latch   <= (control_flags[CTRL_FLAG_DIR] == 0)? registers[7] + 2: registers[7] - 2;
                        end
                    end

                    8'hFA, 8'hFB, 8'hFC, 8'hF3:
                    begin
                    end

                    // Segment override prefix.
                    8'h26, 8'h2E, 8'h36, 8'h3E:
                    begin
                    end

                    default:
                        error <= `__LINE__;
                endcase
            end
            else
            begin
                // ** Handle move source reading **
                if(micro_mov_src == MICRO_MOV_RM && need_modrm && mod != 2'b11)
                begin
                    // Source is memory
                    bus_address     <= physical_address;
                    bus_command     <= BUS_COMMAND_MEM_READ;
                    read_write_wait <= 1;

                    mov_from     <= READ_SRC_MEM;
                    mov_src_size <= byte_word_field;
                end
                else if(micro_mov_src == MICRO_MOV_RM || micro_mov_src == MICRO_MOV_R)
                begin
                    // Source is register specified by modrm.
                    reg_src      <= src_operand[2:0];
                    mov_from     <= src_operand[3]? READ_SRC_SREG: READ_SRC_REG;
                    mov_src_size <= byte_word_field;
                end
                else if(micro_mov_src == MICRO_MOV_IMM)
                begin
                    // Source is immediate.
                    mov_from     <= READ_SRC_IMM;
                    mov_src_size <= imm_size;
                end
                else if(micro_mov_src == MICRO_MOV_DISP)
                begin
                    // Source is disp.
                    mov_from     <= READ_SRC_DISP;
                    mov_src_size <= 1;
                end
                else if(micro_mov_src == MICRO_MOV_ALU_R)
                begin
                    mov_from     <= READ_SRC_ALU;
                    mov_src_size <= 1;
                end
                else if(micro_mov_src >= MICRO_MOV_AW && micro_mov_src <= MICRO_MOV_PC)
                begin
                    // Source is word register
                    mov_src_size  <= 1;

                    if(micro_mov_src  == MICRO_MOV_PC)
                    begin
                        mov_from <= READ_SRC_PC;
                        reg_src  <= 0;
                    end
                    else if(micro_mov_src >= MICRO_MOV_DS1)
                    begin
                        mov_from <= READ_SRC_SREG;
                        reg_src  <= micro_mov_src[2:0];
                    end
                    else
                    begin
                        mov_from <= READ_SRC_REG;
                        reg_src  <= micro_mov_src[2:0];
                    end
                end
                else if(micro_mov_src == MICRO_MOV_ZERO)
                begin
                    mov_src_size <= 1;
                    mov_from     <= READ_SRC_ZERO;
                end
                else if(micro_mov_src == MICRO_MOV_ONES)
                begin
                    mov_src_size <= 1;
                    mov_from     <= READ_SRC_ONES;
                end
                else if(micro_mov_src == MICRO_MOV_TMP)
                begin
                    mov_src_size <= 1;
                    mov_from     <= READ_SRC_TMP;
                end
                else if(micro_mov_src == MICRO_MOV_AL || micro_mov_src == MICRO_MOV_AH)
                begin
                    // Source is byte register
                    reg_src <= micro_mov_src[2:0];
                    mov_src_size <= 0;
                end
                else if(micro_mov_src != MICRO_MOV_NONE)
                    error <= `__LINE__;


                // ** Handle move destination writing **
                if(micro_mov_dst == MICRO_MOV_RM && need_modrm && mod != 2'b11)
                begin
                    // Destination is memory
                    bus_address     <= physical_address;
                    bus_command     <= BUS_COMMAND_MEM_WRITE;
                    data_out        <= mov_data;
                    read_write_wait <= 1;
                    mov_dst_size    <= byte_word_field;
                end
                else if((micro_mov_dst == MICRO_MOV_RM) || (micro_mov_dst == MICRO_MOV_R))
                begin
                    // Destination is register specified by modrm.
                    reg_dst      <= dst_operand[2:0];
                    mov_dst_size <= byte_word_field;
                    if(dst_operand[3])
                        sregfile_we_r <= 1;
                    else
                        regfile_we_r  <= 1;
                end
                else if(micro_mov_dst == MICRO_MOV_ADD)
                begin
                    // @todo @important: We need to handle segment override.
                    // We could even add a flag for enabling/disabling
                    // override?
                    if(segment_override[2])
                        error <= `__LINE__;

                    case(micro_bus_seg)
                        MICRO_BUS_SEG_ZERO:
                            bus_address <= {4'd0, mov_data} + micro_bus_disp_se;
                        MICRO_BUS_SEG_SS:
                            bus_address <= {segment_registers[2], 4'd0} + {4'd0, mov_data} + micro_bus_disp_se;
                        MICRO_BUS_SEG_DS1:
                            bus_address <= {segment_registers[0], 4'd0} + {4'd0, mov_data} + micro_bus_disp_se;
                        MICRO_BUS_SEG_DS0:
                            bus_address <= {segment_registers[3], 4'd0} + {4'd0, mov_data} + micro_bus_disp_se;
                    endcase
                    mov_dst_size <= 1;
                end
                else if(micro_mov_dst == MICRO_MOV_TMP)
                begin
                    temp_latch   <= mov_data_temp;
                    mov_dst_size <= 1;
                end
                else if(micro_mov_dst == MICRO_MOV_ALU_A)
                begin
                    alu_a <= mov_data_temp;
                    mov_dst_size <= byte_word_field;
                end
                else if(micro_mov_dst >= MICRO_MOV_AW && micro_mov_dst <= MICRO_MOV_PC)
                begin
                    // Destination is word register
                    mov_dst_size <= 1;

                    if(micro_mov_dst == MICRO_MOV_PC)
                    begin
                        // @note: Assume we are always moving from word registers.
                        reg_dst <= 0;
                    end
                    else if(micro_mov_dst >= MICRO_MOV_DS1)
                    begin
                        sregfile_we_r <= 1;
                        reg_dst       <= micro_mov_dst[2:0];
                    end
                    else
                    begin
                        regfile_we_r <= 1;
                        reg_dst      <= micro_mov_dst[2:0];
                    end
                end
                else if(micro_mov_dst == MICRO_MOV_AL || micro_mov_dst == MICRO_MOV_AH)
                begin
                    // Destination is byte register
                    regfile_we_r <= 1;
                    reg_dst      <= micro_mov_dst[2:0];
                    mov_dst_size <= 0;
                end
                else if(micro_mov_dst != MICRO_MOV_NONE)
                    error <= `__LINE__;

                // Alu destination operand loading
                if(micro_op_type[2:1] == MICRO_TYPE_ALU)
                begin
                    case(micro_op[9:5])

                        MICRO_MOV_R,
                        MICRO_MOV_RM:
                        begin
                            if(need_modrm && mod != 2'b11)
                            begin
                                // It is implied that the previous microcode
                                // step has loaded the data from memory.
                                alu_b <= data_in;
                            end
                            else
                            begin
                                if(byte_word_field == 1)
                                    alu_b <= registers[dst_operand[2:0]];
                                else if(dst_operand[2] == 0)
                                    alu_b <= {8'd0, registers[{1'd0, dst_operand[1:0]}][7:0]};
                                else
                                    alu_b <= {8'd0, registers[{1'd0, dst_operand[1:0]}][15:8]};
                            end
                        end

                        MICRO_MOV_AL:
                            alu_b <= {8'd0, registers[0][7:0]};
                        MICRO_MOV_AH:
                            alu_b <= {8'd0, registers[0][15:8]};

                        MICRO_MOV_AW, MICRO_MOV_CW, MICRO_MOV_DW, MICRO_MOV_BW,
                        MICRO_MOV_SP, MICRO_MOV_BP, MICRO_MOV_IX, MICRO_MOV_IY:
                            alu_b <= registers[micro_op[9:5][2:0]];

                        MICRO_MOV_PC:
                            alu_b <= PC;

                        // @todo: Can MICRO_MOV_TMP be a destination register?

                        default:
                        begin
                            alu_b <= 16'hCAFE;
                            error <= `__LINE__;
                        end
                    endcase
                end
                // Bus write operation
                else if(micro_bus_write)
                begin
                    case(micro_op[9:5])

                        MICRO_MOV_ONES:
                            data_out <= 1;

                        MICRO_MOV_ZERO:
                            data_out <= 0;

                        MICRO_MOV_RM,
                        MICRO_MOV_R:
                        begin
                            if(need_modrm && mod != 2'b11)
                            begin
                                // It is implied that the previous microcode
                                // step has loaded the data from memory.
                                data_out <= data_in;
                            end
                            else
                            begin
                                if(byte_word_field == 1)
                                    data_out <= registers[src_operand[2:0]];
                                else if(src_operand[2] == 0)
                                    data_out <= {8'd0, registers[{1'd0, src_operand[1:0]}][7:0]};
                                else
                                    data_out <= {8'd0, registers[{1'd0, src_operand[1:0]}][15:8]};
                            end
                        end

                        MICRO_MOV_AL:
                            data_out <= {8'd0, registers[0][7:0]};
                        MICRO_MOV_AH:
                            data_out <= {8'd0, registers[0][15:8]};

                        MICRO_MOV_AW, MICRO_MOV_CW, MICRO_MOV_DW, MICRO_MOV_BW,
                        MICRO_MOV_SP, MICRO_MOV_BP, MICRO_MOV_IX, MICRO_MOV_IY:
                            data_out <= registers[micro_op[9:5][2:0]];

                        MICRO_MOV_DS1,
                        MICRO_MOV_PS,
                        MICRO_MOV_SS,
                        MICRO_MOV_DS0:
                            data_out <= segment_registers[micro_op[9:5][1:0]];

                        MICRO_MOV_PC:
                            data_out <= PC;

                        MICRO_MOV_DISP:
                            data_out <= disp_sign_extended;

                        MICRO_MOV_IMM:
                            data_out <= imm;

                        MICRO_MOV_TMP:
                            data_out <= temp_reg;

                        MICRO_MOV_NONE:;

                        default:
                        begin
                            data_out <= 16'hCAFE;
                            error <= `__LINE__;
                        end
                    endcase
                end
                // Bus read operation
                else if(micro_bus_read)
                begin
                    case(micro_op[9:5])
                        MICRO_MOV_R,
                        MICRO_MOV_RM:
                        begin
                            //@todo: sreg
                            // Destination is register specified by modrm.
                            if(!need_modrm || mod == 2'b11)
                            begin
                                reg_dst      <= src_operand[2:0];
                                mov_dst_size <= byte_word_field;
                                regfile_we_r <= 1;
                            end
                        end

                        MICRO_MOV_AL,
                        MICRO_MOV_AH:
                        begin
                            // Destination is byte register
                            regfile_we_r <= 1;
                            reg_dst      <= micro_op[9:5][2:0];
                            mov_dst_size <= 0;
                        end

                        MICRO_MOV_AW, MICRO_MOV_CW, MICRO_MOV_DW, MICRO_MOV_BW,
                        MICRO_MOV_SP, MICRO_MOV_BP, MICRO_MOV_IX, MICRO_MOV_IY:
                        begin
                            mov_dst_size <= 1;
                            regfile_we_r <= 1;
                            reg_dst      <= micro_op[9:5][2:0];
                        end

                        MICRO_MOV_DS1,
                        MICRO_MOV_PS,
                        MICRO_MOV_SS,
                        MICRO_MOV_DS0:
                        begin
                            mov_dst_size  <= 1;
                            sregfile_we_r <= 1;
                            reg_dst       <= micro_op[9:5][2:0];
                        end

                        MICRO_MOV_PC:
                        begin
                            mov_dst_size  <= 1;
                            reg_dst       <= 0;
                            pc_write_data <= data_in;
                        end

                        MICRO_MOV_TMP:
                        begin
                            mov_dst_size <= 1;
                            temp_latch   <= data_in;
                        end

                        // @todo: Segment registers.

                        MICRO_MOV_NONE:;

                        default:
                            error <= `__LINE__;
                    endcase
                end

                // ** Handle alu register writeback **
                if(micro_op_type[2:1] == MICRO_TYPE_ALU && alu_reg_wb)
                begin
                    if(
                        (micro_op[9:5] == MICRO_MOV_RM || micro_op[9:5] == MICRO_MOV_R) &&
                        (!need_modrm || mod == 2'b11)
                    )
                    begin
                        // Destination is register specified by modrm.
                        reg_dst      <= dst_operand[2:0];
                        mov_dst_size <= byte_word_field;
                        regfile_we_r <= 1;
                    end
                    else if(micro_op[9:5] >= MICRO_MOV_AW && micro_op[9:5] <= MICRO_MOV_PC)
                    begin
                        mov_dst_size <= 1;

                        if(micro_op[9:5] == MICRO_MOV_PC)
                        begin
                            // @todo: Is PC really written to?
                            reg_dst <= 0;
                        end
                        else
                        begin
                            regfile_we_r <= 1;
                            reg_dst      <= micro_op[9:5][2:0];
                        end
                    end
                    else if(micro_op[9:5] == MICRO_MOV_AL || micro_op[9:5] == MICRO_MOV_AH)
                    begin
                        // Destination is byte register
                        regfile_we_r <= 1;
                        reg_dst      <= micro_op[9:5][2:0];
                        mov_dst_size <= 0;
                    end
                    else
                        error <= `__LINE__;
                end

                case(micro_op_type)
                    // Bus operation
                    MICRO_TYPE_BUS:
                    begin
                        read_write_wait <= 1;
                        // @todo: use byte_word_field for bus_upper_byte_enable.
                        // Perhaps just assign it to it.

                        if(micro_mov_src != MICRO_MOV_NONE && micro_op[9:5] != MICRO_MOV_NONE)
                        begin
                            case(micro_bus_op)
                                MICRO_BUS_IO_WRITE:
                                    bus_command <= BUS_COMMAND_IO_WRITE;
                                MICRO_BUS_IO_READ:
                                    bus_command <= BUS_COMMAND_IO_READ;
                                MICRO_BUS_MEM_WRITE:
                                    bus_command <= BUS_COMMAND_MEM_WRITE;
                                MICRO_BUS_MEM_READ:
                                    bus_command <= BUS_COMMAND_MEM_READ;
                            endcase
                        end

                        case(micro_bus_ind)
                            MICRO_BUS_IND_ZERO:;

                            MICRO_BUS_IND_INC1,
                            MICRO_BUS_IND_INC2,
                            MICRO_BUS_IND_DEC1,
                            MICRO_BUS_IND_DEC2:
                            begin
                                if(micro_mov_src == MICRO_MOV_AL || micro_mov_src == MICRO_MOV_AH)
                                begin
                                    regfile_we_r_secondary <= 1;
                                    regfile_write_id_secondary <= micro_mov_src[2:0];
                                    reg_tmp_bus <= (micro_mov_src == MICRO_MOV_AL)?
                                        {8'd0, registers[micro_mov_src[2:0]][7:0]} + micro_bus_ind_offset:
                                        {8'd0, registers[micro_mov_src[2:0]][15:8]} + micro_bus_ind_offset;
                                end
                                else if(micro_mov_src >= MICRO_MOV_AW && micro_mov_src <= MICRO_MOV_IY)
                                begin
                                    regfile_we_r_secondary <= 1;
                                    regfile_write_id_secondary <= micro_mov_src[2:0];
                                    reg_tmp_bus <= registers[micro_mov_src[2:0]] + micro_bus_ind_offset;
                                end
                                else
                                    error <= `__LINE__;
                            end

                            MICRO_BUS_IND_BL:
                            begin
                                if(micro_mov_src >= MICRO_MOV_AW && micro_mov_src <= MICRO_MOV_IY)
                                begin
                                    regfile_we_r_secondary <= 1;
                                    regfile_write_id_secondary <= micro_mov_src[2:0];

                                    if(byte_word_field == 1)
                                    begin
                                        reg_tmp_bus <= (control_flags[CTRL_FLAG_DIR] == 0)?
                                            registers[micro_mov_src[2:0]] + 2:
                                            registers[micro_mov_src[2:0]] - 2;
                                    end
                                    else
                                    begin
                                        reg_tmp_bus <= (control_flags[CTRL_FLAG_DIR] == 0)?
                                            registers[micro_mov_src[2:0]] + 1:
                                            registers[micro_mov_src[2:0]] - 1;
                                    end
                                end
                                else
                                    error <= `__LINE__;
                            end

                            default:
                                error <= `__LINE__;
                        endcase
                    end
                    // alu operation
                    3'b010, 3'b011:
                    begin
                        alu_size    <= byte_word_field;
                        // @todo: We probably need to add flag for updating flags
                        // or not.
                        alu_flags_r <= alu_flags;

                        case(micro_alu_op)
                            MICRO_ALU_OP_XI:
                                alu_op <=
                                     (opcode[7:4] == 4'b1000)?    {2'b0, regm}:
                                    ((opcode[7:2] == 6'b110100)?  ALUOP_ROL + {2'b0, regm}:
                                    ((opcode[7:1] == 7'b1100000)? ALUOP_ROL + {2'b0, regm}:
                                    ((opcode[7:1] == 7'b1111111)? ALUOP_INC + {2'b0, regm}:
                                    ((opcode[7:4] == 4'b0100)?    ALUOP_INC + {2'b0, opcode[5:3]}:
                                                                  {2'b0, opcode[5:3]}))));

                            MICRO_ALU_OP_AND:
                                alu_op <= ALUOP_AND;

                            MICRO_ALU_OP_ADD:
                                alu_op <= ALUOP_ADD;

                            MICRO_ALU_OP_SUB:
                                alu_op <= ALUOP_SUB;

                            MICRO_ALU_OP_INC:
                                alu_op <= ALUOP_INC;

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

                    default:;

                endcase
            end
        end
    end

    always_ff @ (posedge clk)
    begin
        if(reset)
        begin
            microprogram_counter <= 0;
            microaddress         <= 0;
            PC                   <= 16'h0000;
            state                <= STATE_OPCODE_READ;
        end
        else
        begin
            queue_flush   <= 0;
            queue_suspend <= 0;
            branch_taken  <= 0;

            // @todo: Allow reading when instruction is done or nearly done.
            // Perhaps we can achieve this by removing the execute state,
            // making the current states only for reading the opcode bytes,
            // and having a separate reg enabled when executing. The reg is
            // enabled when next_state == STATE_OPCODE_READ. The state of the
            // opcode reader is then set to next_state only when
            // instruction_maybe_done or instruction_nearly_done. The following
            // should work, but I think it will only give benefits when we
            // have instructions that set instruction_nearly_done.
            //
            // if(!queue_empty && (instruction_maybe_done || instruction_nearly_done))
            // begin
            //     // Get instruction from queue_buffer if it's not empty.
            //     if(state == STATE_OPCODE_READ)
            //         PC <= PC + 1;
            //     if(next_state == STATE_OPCODE_READ)
            //         execute <= 1;

            //     state <= next_state;
            // end

            if(state <= STATE_IMM_HIGH_READ)
            begin
                if(state == STATE_OPCODE_READ)
                    microaddress  <= translation_rom[opcode];

                // Handle Group 2 instructions
                if(state == STATE_MODRM_READ && (opcode[7:1] == 7'h7F))
                begin
                    case(regm)
                        3'b000, 3'b001: // INC/DEC
                            microaddress <= 17; // @todo: Make address robust.

                        // @Implement other instructions.

                        default:
                            cerror <= `__LINE__;
                    endcase
                end

                // @note: I thought there might be a problem here using
                // sequential logic: If the queue is empty on this cycle but
                // receiving data the next cycle, queue_empty will be false
                // only on the next rising edge, meaning that the state will
                // move forward at the following cycle.
                //                __    __    __
                // clk           /  \__/  \__/  \
                //                ______
                // data_request  |      |________
                //               _______
                // queue_empty          |________
                //               .................
                // state         ............/....
                //
                // But, I think there is nothing we can do, as the queue is
                // updated on the positive edge of the clock anyway?

                // Make sure the queue is not empty at any of the read states.
                if(!queue_empty && !queue_flush)
                begin
                    // Get instruction from queue_buffer if it's not empty.
                    PC <= PC + 1;
                    state <= next_state;
                end
            end
            // STATE_EXECUTE
            else if(!read_write_wait || bus_command_done)
            begin
                if(instruction_maybe_done && (!instruction_repeat || registers[1] == 0))
                    state <= next_state;

                if(micro_mov_dst == MICRO_MOV_PC)
                    PC <= mov_data;

                // @note: In case of bus or alu operation.
                if(micro_mov_dst == MICRO_MOV_TMP || (micro_bus_read && micro_op[9:5] == MICRO_MOV_TMP))
                    temp_reg <= temp_latch;

                // @todo: Do the same for alu writeback?
                if(micro_bus_read && micro_op[9:5] == MICRO_MOV_PC)
                    PC <= pc_write_data;

                segment_override <= 0;

                // @todo: Check that we stop on time, or not
                // a clock too late.
                if(instruction_repeat && registers[1] != 0)
                begin
                    state <= STATE_EXECUTE;
                end
                else
                    instruction_repeat <= 0;

                if(translation_rom[opcode] == 0 && opcode[7:1] != 7'h7F)
                begin
                    case(opcode)
                        8'hF3:
                        begin
                            if(registers[1] == 0)
                            begin
                                PC <= PC + 2;
                            end
                            else
                            begin
                                instruction_repeat <= 1;
                            end
                        end

                        8'hFA:
                            control_flags[CTRL_FLAG_IE] <= 0;

                        8'hFB:
                            control_flags[CTRL_FLAG_IE] <= 1;

                        8'hFC:
                            control_flags[CTRL_FLAG_DIR] <= 0;

                        8'hA5,
                        8'hAB:
                        begin
                            // @todo: Check if the second check is superfluous.
                            if(instruction_step != 1 || bus_command_done)
                                instruction_step <= (instruction_step + 1) % 3;
                        end

                        // Segment override prefix.
                        8'h26, 8'h2E, 8'h36, 8'h3E:
                        begin
                            segment_override <= {1'b1, opcode[4:3]};
                        end

                        default;
                    endcase
                end
                else
                begin
                    if(instruction_maybe_done)
                        microprogram_counter <= 0;
                    else
                        microprogram_counter <= microprogram_counter + 1;

                    // Handle microcode commands
                    // @note: Not sure if I need to handle all these types of
                    // microcode instructions. Certain jumps were introduced in
                    // 8086 to reduce the microcode size, but this is not a huge
                    // problem here.
                    case(micro_op_type)

                        // misc
                        MICRO_TYPE_MISC:
                        begin
                            if(micro_misc_op_a == MICRO_MISC_OP_A_FLUSH)
                                queue_flush <= 1;

                            if(micro_misc_op_b == MICRO_MISC_OP_B_SUSP)
                                queue_suspend <= 1;
                        end

                        // alu
                        3'b010, 3'b011:
                        begin
                        end

                        // long jump
                        MICRO_TYPE_JMP:
                        begin
                            case(micro_jmp_condition)
                                MICRO_JMP_XC:
                                begin
                                    case(opcode[3:0])
                                        4'h2: // BC
                                        begin
                                            if(alu_flags_r[ALU_FLAG_CY] == 1)
                                            begin
                                                microprogram_counter <= 0;
                                                microaddress <= jump_table[micro_jmp_destination];
                                                branch_taken <= 1;
                                                state <= STATE_EXECUTE;
                                            end
                                        end

                                        4'h3: // BNC
                                        begin
                                            if(alu_flags_r[ALU_FLAG_CY] == 0)
                                            begin
                                                microprogram_counter <= 0;
                                                microaddress <= jump_table[micro_jmp_destination];
                                                branch_taken <= 1;
                                                state <= STATE_EXECUTE;
                                            end
                                        end

                                        4'h4: // BZ
                                        begin
                                            if(alu_flags_r[ALU_FLAG_Z] == 1)
                                            begin
                                                microprogram_counter <= 0;
                                                microaddress <= jump_table[micro_jmp_destination];
                                                branch_taken <= 1;
                                                state <= STATE_EXECUTE;
                                            end
                                        end

                                        4'h5: // BNZ
                                        begin
                                            if(alu_flags_r[ALU_FLAG_Z] == 0)
                                            begin
                                                microprogram_counter <= 0;
                                                microaddress <= jump_table[micro_jmp_destination];
                                                branch_taken <= 1;
                                                state <= STATE_EXECUTE;
                                            end
                                        end

                                        default:
                                        begin
                                        end
                                    endcase
                                end

                                MICRO_JMP_NZ:
                                begin
                                    if(alu_flags_r[ALU_FLAG_Z] == 0)
                                    begin
                                        microprogram_counter <= 0;
                                        microaddress <= jump_table[micro_jmp_destination];
                                        branch_taken <= 1;
                                        state <= STATE_EXECUTE;
                                    end
                                end

                                MICRO_JMP_UC:
                                begin
                                    microprogram_counter <= 0;
                                    microaddress <= jump_table[micro_jmp_destination];
                                    branch_taken <= 1;
                                    state <= STATE_EXECUTE;
                                end

                                default:
                                begin
                                end
                            endcase
                        end

                        // bus operation
                        MICRO_TYPE_BUS:
                        begin
                        end

                        // short jump
                        3'b000, 3'b001:
                        begin
                            if(micro_sjmp_condition == MICRO_SJMP_NREP && !instruction_repeat)
                            begin
                                microprogram_counter <= 0;
                                microaddress <= microaddress + {{4{micro_sjmp_offset[4]}}, micro_sjmp_offset};
                                branch_taken <= 1;
                                state <= STATE_EXECUTE;
                            end
                        end

                        // long call (@note: Will probably not implement)
                        3'b111:
                        begin
                        end

                    endcase
                end
            end
        end
    end

endmodule;
