enum [4:0]
{
    //ALUOP_PASS_A,
    //ALUOP_PASS_B,
    ALUOP_ADD  = 5'd0,
    ALUOP_OR   = 5'd1,
    ALUOP_ADDC = 5'd2,
    ALUOP_SUBC = 5'd3,
    ALUOP_AND  = 5'd4,
    ALUOP_SUB  = 5'd5,
    ALUOP_XOR  = 5'd6,
    ALUOP_CMP  = 5'd7,

    ALUOP_ROL  = 5'd8,
    ALUOP_ROR  = 5'd9,
    ALUOP_ROLC = 5'd10,
    ALUOP_RORC = 5'd11,
    ALUOP_SHL  = 5'd12,
    ALUOP_SHR  = 5'd13,
    ALUOP_SHLA = 5'd14, // Does not exist, just ALUOP_SHL
    ALUOP_SHRA = 5'd15,

    ALUOP_INC  = 5'd16,
    ALUOP_DEC  = 5'd17,
    ALUOP_NEG  = 5'd18
} AluOp;

enum [2:0]
{
    ALU_FLAG_AC,  // Auxiliary carry flag
    ALU_FLAG_CY,  // Carry flag
    ALU_FLAG_V,   // Overflow flag
    ALU_FLAG_P,   // Parity flag
    ALU_FLAG_S,   // Sign flag
    ALU_FLAG_Z    // Zero flag
} AluFlags;


module alu
(
    input [4:0] alu_op,
    input size,
    input [15:0] A,
    input [15:0] B,
    output reg [15:0] R,
    output reg [5:0] flags
);

    function [15:0] rol
    (
        input byte_or_word,
        input [15:0] x, input [15:0] s
    );
        if(byte_or_word == 0)
        begin
            case(s[3:0])
                1:
                    rol = {x[14:0], x[7]};
                2:
                    rol = {x[13:0], x[7:6]};
                3:
                    rol = {x[12:0], x[7:5]};
                4:
                    rol = {x[11:0], x[7:4]};
                5:
                    rol = {x[10:0], x[7:3]};
                6:
                    rol = {x[9:0], x[7:2]};
                7:
                    rol = {x[8:0], x[7:1]};
                default:
                    rol = x;
            endcase
        end
        else
        begin
            case(s[4:0])
                1:
                    rol = {x[14:0], x[15]};
                2:
                    rol = {x[13:0], x[15:14]};
                3:
                    rol = {x[12:0], x[15:13]};
                4:
                    rol = {x[11:0], x[15:12]};
                5:
                    rol = {x[10:0], x[15:11]};
                6:
                    rol = {x[9:0], x[15:10]};
                7:
                    rol = {x[8:0], x[15:9]};
                8:
                    rol = {x[7:0], x[15:8]};
                9:
                    rol = {x[6:0], x[15:7]};
                10:
                    rol = {x[5:0], x[15:6]};
                11:                                     
                    rol = {x[4:0], x[15:5]};
                12:                                     
                    rol = {x[3:0], x[15:4]};
                13:                                     
                    rol = {x[2:0], x[15:3]};
                14:
                    rol = {x[1:0], x[15:2]};
                15:                                    
                    rol = {x[0], x[15:1]};
                default:
                    rol = x;
            endcase
        end
    endfunction

    function [15:0] ror
    (
        input byte_or_word,
        input [15:0] x, input [15:0] s
    );
        if(byte_or_word == 0)
        begin
            case(s[3:0])
                1:
                    ror = {x[15:8], x[0],   x[7:1]};
                2:
                    ror = {x[15:8], x[1:0], x[7:2]};
                3:
                    ror = {x[15:8], x[2:0], x[7:3]};
                4:
                    ror = {x[15:8], x[3:0], x[7:4]};
                5:
                    ror = {x[15:8], x[4:0], x[7:5]};
                6:
                    ror = {x[15:8], x[5:0], x[7:6]};
                7:
                    ror = {x[15:8], x[6:0], x[7]};
                default:
                    ror = x;
            endcase
        end
        else
        begin
            case(s[4:0])
                1:
                    ror = {x[0],   x[15:1]};
                2:
                    ror = {x[1:0], x[15:2]};
                3:
                    ror = {x[2:0], x[15:3]};
                4:
                    ror = {x[3:0], x[15:4]};
                5:
                    ror = {x[4:0], x[15:5]};
                6:
                    ror = {x[5:0], x[15:6]};
                7:
                    ror = {x[6:0], x[15:7]};
                8:
                    ror = {x[7:0], x[15:8]};
                9:
                    ror = {x[8:0], x[15:9]};
                10:
                    ror = {x[9:0], x[15:10]};
                11:
                    ror = {x[10:0], x[15:11]};
                12:
                    ror = {x[11:0], x[15:12]};
                13:
                    ror = {x[12:0], x[15:13]};
                14:
                    ror = {x[13:0], x[15:14]};
                15:
                    ror = {x[14:0], x[15]};
                default:
                    ror = x;
            endcase
        end
    endfunction

    function parity(input [15:0] x);
        parity = ~(x[0] ^ x[1] ^ x[2] ^ x[3] ^ x[4] ^ x[5] ^ x[6] ^ x[7]);
    endfunction

    // @question: When size == 0, do we modify the contents of the upper byte?
    // Does it matter at all if we write back only the lower byte anyway?
    // I would guess not.

    // @question: Is it better to use non-blocking assigns and set flags based
    // strictly on the input data, or using blocking assignments with extended
    // by-1-bit data and use the result for the carry?

    // @todo: What's the correct way to handle 0 shifts?

    wire [3:0] msb = (size == 0)? 4'd7: 4'd15;

    always_comb
    begin
        case(alu_op)

            ALUOP_AND:
            begin
                R = B & A;
                flags[ALU_FLAG_CY] = 0;
                flags[ALU_FLAG_V]  = 0;
                flags[ALU_FLAG_Z]  = (R == 0);
                flags[ALU_FLAG_P]  = parity(R);
                flags[ALU_FLAG_S]  = R[msb];
            end

            ALUOP_INC,
            ALUOP_ADD:
            begin
                if(alu_op == ALUOP_ADD)
                    {flags[ALU_FLAG_CY], R} = {1'b0, B} + {1'b0, A};
                else
                    R = B + A;

                flags[ALU_FLAG_V] = (A[msb] == B[msb]) && (R[msb] != B[msb]);
                // can we do this? flags[ALU_FLAG_V] = (R[msb] == flags[ALU_FLAG_CY]);
                flags[ALU_FLAG_Z] = (R == 0);
                flags[ALU_FLAG_P] = parity(R);
                flags[ALU_FLAG_S] = R[msb];
            end

            ALUOP_DEC,
            ALUOP_CMP,
            ALUOP_SUB:
            begin
                R = B - A;
                if(alu_op != ALUOP_DEC)
                    flags[ALU_FLAG_CY] = (B < A);

                flags[ALU_FLAG_V] = (A[msb] != B[msb]) && (R[msb] != B[msb]);
                flags[ALU_FLAG_Z] = (R == 0);
                flags[ALU_FLAG_P] = parity(R);
                flags[ALU_FLAG_S] = R[msb];
            end

            ALUOP_XOR:
            begin
                R = B ^ A;

                flags[ALU_FLAG_CY] = 0;
                flags[ALU_FLAG_V]  = 0;

                flags[ALU_FLAG_P] = parity(R);
                flags[ALU_FLAG_Z] = (R == 0);
                flags[ALU_FLAG_S] = R[msb];
            end

            ALUOP_ROL:
            begin
                R = rol(size, B, A);
                flags[ALU_FLAG_CY] = R[msb];
                if(A[msb] == R[msb]) flags[ALU_FLAG_V] = 0;
            end

            ALUOP_ROR:
            begin
                R = ror(size, B, A);
                flags[ALU_FLAG_CY] = R[0];
                if(A[msb] == R[msb]) flags[ALU_FLAG_V] = 0;
            end

            ALUOP_SHL:
            begin
                if(A == 1)
                begin
                    R = {B[14:0], 1'b0};
                    flags[ALU_FLAG_CY] = B[msb];
                    if(B[msb] == B[msb-1]) flags[ALU_FLAG_V] = 0;
                end
                else
                begin
                    R = (B << A[4:0]);
                    if(A > 0) flags[ALU_FLAG_CY] = B[msb - A[4:0] + 1];
                end

                flags[ALU_FLAG_Z] = (R == 0);
                flags[ALU_FLAG_S] = R[msb];
                flags[ALU_FLAG_P] = parity(R);
            end

            ALUOP_SHR:
            begin
                if(A == 1)
                begin
                    R = (size == 0)?
                        {B[15:8], 1'b0, B[7:1]}:
                        {1'b0, B[15:1]};

                    flags[ALU_FLAG_CY] = B[0];

                    if(B[msb] == 0) flags[ALU_FLAG_V] = 0;
                end
                else
                begin
                    R = (B >> A[4:0]);
                    if(A > 0) flags[ALU_FLAG_CY] = B[A[4:0]-1];
                end

                flags[ALU_FLAG_Z] = (R == 0);
                flags[ALU_FLAG_S] = R[msb];
                flags[ALU_FLAG_P] = parity(R);
            end

            default:
                R = 16'hFACE;

        endcase
    end

endmodule
