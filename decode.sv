
module decode
(
    input [7:0] opcode,
    input [7:0] opext,
    output reg need_opext,
    output reg need_imm,
    output reg imm_size
);


    /* verilator lint_off COMBDLY  */
    always_comb
    begin
        casez(opcode)
            8'b0000_00??: // ADD R/M R
            begin
                need_opext <= 1;
                need_imm   <= 0;
                imm_size   <= 0;
            end

            default:
            begin
                need_opext <= 0;
                need_imm   <= 0;
                imm_size   <= 0;
            end
        endcase
    end

endmodule;
