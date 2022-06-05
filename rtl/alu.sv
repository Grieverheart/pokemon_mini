enum [4:0]
{
    ALUOP_ADD  = 5'd0,
    ALUOP_OR   = 5'd1,
    ALUOP_ADC  = 5'd2,
    ALUOP_SBC  = 5'd3,
    ALUOP_AND  = 5'd4,
    ALUOP_SUB  = 5'd5,
    ALUOP_XOR  = 5'd6,

    ALUOP_RLC  = 5'd8,
    ALUOP_RRC  = 5'd9,
    ALUOP_RL   = 5'd10,
    ALUOP_RR   = 5'd11,
    ALUOP_SLL  = 5'd12,
    ALUOP_SRL  = 5'd13,
    ALUOP_SLA  = 5'd14,
    ALUOP_SRA  = 5'd15,

    ALUOP_INC  = 5'd16,
    ALUOP_INC2 = 5'd17,
    ALUOP_DEC  = 5'd18,
    ALUOP_DEC2 = 5'd19,
    ALUOP_NEG  = 5'd20,

    ALUOP_DIV  = 5'd21,
    ALUOP_MUL  = 5'd22
} AluOp;

enum [1:0]
{
    ALU_FLAG_Z,  // Zero flag
    ALU_FLAG_C,  // Carry flag
    ALU_FLAG_V,  // Overflow flag
    ALU_FLAG_S   // Sign flag
} AluFlags;


// @todo: Need to implement decimal and unpack operations.
module alu
(
    input [4:0] alu_op,
    input size,
    input [15:0] A,
    input [15:0] B,
    input C,
    output reg [15:0] R,
    output reg [3:0] flags
);

    // @question: When size == 0, do we modify the contents of the upper byte?
    // Does it matter at all if we write back only the lower byte anyway?
    // I would guess not.

    // @question: Is it better to use non-blocking assigns and set flags based
    // strictly on the input data, or using blocking assignments with extended
    // by-1-bit data and use the result for the carry?

    // @todo: What's the correct way to handle 0 shifts?

    wire [3:0] msb = (size == 0)? 4'd7: 4'd15;
    reg [16:0] R_temp;

    // Should we put flags in separate always_comb? It's annoying that we have
    // to check again if it's ADD, INC, etc.
    always_comb
    begin
        R_temp = 0;
        flags = 4'h0;
        case(alu_op)

            ALUOP_AND:
            begin
                R = A & B;
                flags[ALU_FLAG_C] = 0;
                flags[ALU_FLAG_V] = 0;
                flags[ALU_FLAG_Z] = (R == 0);
                flags[ALU_FLAG_S] = R[msb];
            end

            ALUOP_OR:
            begin
                R = A | B;
                flags[ALU_FLAG_C] = 0;
                flags[ALU_FLAG_V] = 0;
                flags[ALU_FLAG_Z] = (R == 0);
                flags[ALU_FLAG_S] = R[msb];
            end

            ALUOP_XOR:
            begin
                R = A ^ B;
                flags[ALU_FLAG_C] = 0;
                flags[ALU_FLAG_V] = 0;
                flags[ALU_FLAG_Z] = (R == 0);
                flags[ALU_FLAG_S] = R[msb];
            end

            ALUOP_INC,
            ALUOP_INC2,
            ALUOP_ADD,
            ALUOP_ADC:
            begin
                if(alu_op == ALUOP_ADD)
                begin
                    R_temp = {1'b0, A} + {1'b0, B};
                    R = R_temp[15:0];
                    flags[ALU_FLAG_C] = R_temp[{1'b0, msb} + 5'd1];
                end
                else if(alu_op == ALUOP_ADC)
                begin
                    R_temp = {1'b0, A} + {1'b0, B} + {16'd0, C};
                    R = R_temp[15:0];
                    flags[ALU_FLAG_C] = R_temp[{1'b0, msb} + 5'd1];
                end
                else if(alu_op == ALUOP_INC)
                    R = A + 1;
                else
                    R = A + 2;

                flags[ALU_FLAG_V] = (A[msb] & B[msb] & ~R[msb]) | (~A[msb] & ~B[msb] & R[msb]);
                // can we do this? flags[ALU_FLAG_V] = (R[msb] == flags[ALU_FLAG_C]);
                flags[ALU_FLAG_Z] = (R == 0);
                flags[ALU_FLAG_S] = R[msb];
            end

            ALUOP_DEC,
            ALUOP_DEC2,
            ALUOP_NEG,
            ALUOP_SUB,
            ALUOP_SBC:
            begin
                if(alu_op == ALUOP_DEC)
                    R = A - 1;
                else if(alu_op == ALUOP_DEC2)
                    R = A - 2;
                else if(alu_op == ALUOP_SBC)
                begin
                    R_temp = {1'b0, A} - {1'b0, B} - {16'd0, C};
                    R = R_temp[15:0];
                    flags[ALU_FLAG_C] = R_temp[{1'b0, msb} + 5'd1];
                end
                else
                begin
                    R_temp = {1'b0, A} - {1'b0, B};
                    R = R_temp[15:0];
                    flags[ALU_FLAG_C] = R_temp[{1'b0, msb} + 5'd1];
                end

                flags[ALU_FLAG_V] = (A[msb] & ~B[msb] & ~R[msb]) | (~A[msb] & B[msb] & R[msb]);
                flags[ALU_FLAG_Z] = (R == 0);
                flags[ALU_FLAG_S] = R[msb];
            end

            ALUOP_DIV:
            begin
                R_temp[15:0] = A / {{8{B[7]}}, B[7:0]};
                R = flags[ALU_FLAG_V]? A: {A[7:0] % B[7:0], R_temp[7:0]};

                flags[ALU_FLAG_Z] = (B[7:0] != 0)? (R == 0): 0;
                flags[ALU_FLAG_C] = 0;
                flags[ALU_FLAG_V] = (B[7:0] != 0)? (R_temp[15:8] != 0): 1;
                flags[ALU_FLAG_S] = (B[7:0] != 0)? R[7]: 1;
            end

            ALUOP_MUL:
            begin
                R = A[7:0] * B[7:0];

                flags[ALU_FLAG_Z] = (R == 0);
                flags[ALU_FLAG_C] = 0;
                flags[ALU_FLAG_V] = 0;
                flags[ALU_FLAG_S] = R[15];
            end

            ALUOP_RLC:
            begin
                R = {A[14:0], A[msb]};
                flags[ALU_FLAG_C] = A[msb];
                flags[ALU_FLAG_Z] = (R == 0);
                flags[ALU_FLAG_S] = R[msb];
            end

            ALUOP_RL:
            begin
                R = {A[14:0], C};
                flags[ALU_FLAG_C] = A[msb];
                flags[ALU_FLAG_Z] = (R == 0);
                flags[ALU_FLAG_S] = R[msb];
            end

            ALUOP_RRC:
            begin
                R = {A[15:8], A[0], A[7:1]};
                flags[ALU_FLAG_C] = A[0];
                flags[ALU_FLAG_Z] = (R == 0);
                flags[ALU_FLAG_S] = R[msb];
            end

            ALUOP_RR:
            begin
                R = {A[15:8], C, A[7:1]};
                flags[ALU_FLAG_C] = A[0];
                flags[ALU_FLAG_Z] = (R == 0);
                flags[ALU_FLAG_S] = R[msb];
            end

            ALUOP_SLL:
            begin
                R = {A[14:0], 1'b0};
                flags[ALU_FLAG_C] = A[msb];
                flags[ALU_FLAG_Z] = (R == 0);
                flags[ALU_FLAG_S] = R[msb];
            end

            ALUOP_SLA:
            begin
                R = {A[14:0], 1'b0};
                flags[ALU_FLAG_C] = A[msb];
                flags[ALU_FLAG_Z] = (R == 0);
                flags[ALU_FLAG_S] = R[msb];
                flags[ALU_FLAG_V] = (A[msb] ^ A[msb-1]);
            end

            ALUOP_SRL:
            begin
                R = {9'b0, A[7:1]};
                flags[ALU_FLAG_C] = A[0];
                flags[ALU_FLAG_Z] = (R == 0);
                flags[ALU_FLAG_S] = R[msb];
            end

            ALUOP_SRA:
            begin
                R = {9'b0, A[7:1]};
                flags[ALU_FLAG_C] = A[0];
                flags[ALU_FLAG_Z] = (R == 0);
                flags[ALU_FLAG_S] = R[msb];
                flags[ALU_FLAG_V] = 0;
            end

            default:
            begin
                R = 16'hFECA;
                flags = 4'd0;
            end

        endcase
    end

endmodule
