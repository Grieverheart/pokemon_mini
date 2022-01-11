
module decode
(
    input [7:0] opcode,
    input [7:0] opext,
    output reg need_opext,
    output reg need_imm,
    output reg imm_size,
    output wire error
);
    reg need_imm_ext;
    reg imm_size_ext;
    reg error_temp;
    reg error_ext_temp;

    assign error = ((error_ext_temp && need_opext) || error_temp);

    /* verilator lint_off COMBDLY  */
    always_comb
    begin
        error_ext_temp <= 0;

        case({opcode, opext})
            // One-byte opcodes:
            16'hCE02, 16'hCE03, 16'hCE04, 16'hCE06, 16'hCE07, 16'hCE0A, 16'hCE0B, 16'hCE0C, 16'hCE0E, 16'hCE0F,
            16'hCE12, 16'hCE13, 16'hCE14, 16'hCE16, 16'hCE17, 16'hCE1A, 16'hCE1B, 16'hCE1C, 16'hCE1E, 16'hCE1F,
            16'hCE22, 16'hCE23, 16'hCE24, 16'hCE26, 16'hCE27, 16'hCE2A, 16'hCE2B, 16'hCE2C, 16'hCE2E, 16'hCE2F,
            16'hCE32, 16'hCE33, 16'hCE34, 16'hCE36, 16'hCE37, 16'hCE3A, 16'hCE3B, 16'hCE3C, 16'hCE3E, 16'hCE3F,
            16'hCE42, 16'hCE43, 16'hCE46, 16'hCE47, 16'hCE4A, 16'hCE4B, 16'hCE4E, 16'hCE4F,
            16'hCE52, 16'hCE53, 16'hCE56, 16'hCE57, 16'hCE5A, 16'hCE5B, 16'hCE5E, 16'hCE5F,
            16'hCE62, 16'hCE63, 16'hCE6A, 16'hCE6B,
            16'hCE7A, 16'hCE7B,
            16'hCE80, 16'hCE81, 16'hCE83, 16'hCE84, 16'hCE85, 16'hCE87, 16'hCE88, 16'hCE89, 16'hCE8B, 16'hCE8C, 16'hCE8D, 16'hCE8F,
            16'hCE90, 16'hCE91, 16'hCE93, 16'hCE94, 16'hCE95, 16'hCE97, 16'hCE98, 16'hCE99, 16'hCE9B, 16'hCE9C, 16'hCE9D, 16'hCE9F,
            16'hCEA0, 16'hCEA1, 16'hCEA3, 16'hCEA4, 16'hCEA5, 16'hCEA7, 16'hCEA8, 16'hCEAE, 16'hCEAF,
            16'hCEC0, 16'hCEC1, 16'hCEC2, 16'hCEC3, 16'hCEC8, 16'hCEC9, 16'hCECA, 16'hCECB, 16'hCECC, 16'hCECD, 16'hCECE, 16'hCECF,
            16'hCED8, 16'hCED9,
            16'hCF00, 16'hCF01, 16'hCF02, 16'hCF03, 16'hCF04, 16'hCF05, 16'hCF06, 16'hCF07, 16'hCF08, 16'hCF09, 16'hCF0A, 16'hCF0B, 16'hCF0C, 16'hCF0D, 16'hCF0E, 16'hCF0F,
            16'hCF18, 16'hCF19, 16'hCF1A, 16'hCF1B,
            16'hCF20, 16'hCF21, 16'hCF22, 16'hCF23, 16'hCF24, 16'hCF25, 16'hCF26, 16'hCF27, 16'hCF28, 16'hCF29, 16'hCF2A, 16'hCF2B, 16'hCF2C, 16'hCF2D, 16'hCF2E, 16'hCF2F,
            16'hCF38, 16'hCF39, 16'hCF3A, 16'hCF3B,
            16'hCF40, 16'hCF41, 16'hCF42, 16'hCF43, 16'hCF44, 16'hCF45, 16'hCF48, 16'hCF49, 16'hCF4A, 16'hCF4B, 16'hCF4C, 16'hCF4D,
            16'hCF5C, 16'hCF5D,
            16'hCFB0, 16'hCFB1, 16'hCFB2, 16'hCFB3, 16'hCFB4, 16'hCFB5, 16'hCFB6, 16'hCFB7, 16'hCFB8, 16'hCFB9, 16'hCFBC, 16'hCFBD,
            16'hCFC0, 16'hCFC1, 16'hCFC2, 16'hCFC3, 16'hCFC4, 16'hCFC5, 16'hCFC6, 16'hCFC7,
            16'hCFD0, 16'hCFD1, 16'hCFD2, 16'hCFD3, 16'hCFD4, 16'hCFD5, 16'hCFD6, 16'hCFD7, 16'hCFD8, 16'hCFD9, 16'hCFDA, 16'hCFDB, 16'hCFDC, 16'hCFDD, 16'hCFDE, 16'hCFDF,
            16'hCFE0, 16'hCFE1, 16'hCFE2, 16'hCFE3, 16'hCFE4, 16'hCFE5, 16'hCFE6, 16'hCFE7, 16'hCFE8, 16'hCFE9, 16'hCFEA, 16'hCFEB, 16'hCFEC, 16'hCFED, 16'hCFEE, 16'hCFEF,
            16'hCFF0, 16'hCFF1, 16'hCFF3, 16'hCFF4, 16'hCFF5, 16'hCFF8, 16'hCFF9, 16'hCFFA, 16'hCFFE:
            begin
                need_imm_ext <= 0;
                imm_size_ext <= 0;
            end

            // Opcodes with one 8-bit operand:
            16'hCE00, 16'hCE01, 16'hCE05, 16'hCE08, 16'hCE09, 16'hCE0D, 
            16'hCE10, 16'hCE11, 16'hCE15, 16'hCE18, 16'hCE19, 16'hCE1D, 
            16'hCE20, 16'hCE21, 16'hCE25, 16'hCE28, 16'hCE29, 16'hCE2D, 
            16'hCE30, 16'hCE31, 16'hCE35, 16'hCE38, 16'hCE39, 16'hCE3D, 
            16'hCE40, 16'hCE41, 16'hCE44, 16'hCE45, 16'hCE48, 16'hCE49, 16'hCE4C, 16'hCE4D, 
            16'hCE50, 16'hCE51, 16'hCE54, 16'hCE55, 16'hCE58, 16'hCE59, 16'hCE5C, 16'hCE5D, 
            16'hCE60, 16'hCE61, 16'hCE68, 16'hCE69, 
            16'hCE78, 16'hCE79, 
            16'hCE82, 16'hCE86, 16'hCE8A, 16'hCE8E, 
            16'hCE92, 16'hCE96, 16'hCE9A, 16'hCE9E, 
            16'hCEA2, 16'hCEA6, 
            16'hCEB0, 16'hCEB1, 16'hCEB2, 16'hCEB4, 16'hCEB5, 16'hCEB6, 16'hCEB8, 16'hCEB9, 16'hCEBA, 16'hCEBC, 16'hCEBD, 16'hCEBE, 16'hCEBF, 
            16'hCEC4, 16'hCEC5, 16'hCEC6, 16'hCEC7, 
            16'hCEE0, 16'hCEE1, 16'hCEE2, 16'hCEE3, 16'hCEE4, 16'hCEE5, 16'hCEE6, 16'hCEE7, 16'hCEE8, 16'hCEE9, 16'hCEEA, 16'hCEEB, 16'hCEEC, 16'hCEED, 16'hCEEE, 16'hCEEF,
            16'hCEF0, 16'hCEF1, 16'hCEF2, 16'hCEF3, 16'hCEF4, 16'hCEF5, 16'hCEF6, 16'hCEF7, 16'hCEF8, 16'hCEF9, 16'hCEFA, 16'hCEFB, 16'hCEFC, 16'hCEFD, 16'hCEFE, 16'hCEFF, 
            16'hCF70, 16'hCF71, 16'hCF72, 16'hCF73, 16'hCF74, 16'hCF75, 16'hCF76, 16'hCF77:
            begin
                need_imm_ext <= 1;
                imm_size_ext <= 0;
            end

            // Opcodes with two 8-bit operand:
            16'hCED0, 16'hCED1, 16'hCED2, 16'hCED3, 16'hCED4, 16'hCED5, 16'hCED6, 16'hCED7, 
            16'hCF60, 16'hCF61, 16'hCF62, 16'hCF63, 16'hCF68, 16'hCF6A, 16'hCF6C, 16'hCF6E, 
            16'hCF78, 16'hCF7C:
            begin
                need_imm_ext <= 1;
                imm_size_ext <= 1;
            end

            default:
            begin
                error_ext_temp <= 1;
                need_imm_ext <= 0;
                imm_size_ext <= 0;
            end
        endcase
    end

    /* verilator lint_off COMBDLY  */
    always_comb
    begin
        error_temp <= 0;

        case(opcode)
            // One-byte opcodes:
            8'h00, 8'h01, 8'h03, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0B, 8'h0E, 8'h0F,
            8'h10, 8'h11, 8'h13, 8'h16, 8'h17, 8'h18, 8'h19, 8'h1B, 8'h1E, 8'h1F,
            8'h20, 8'h21, 8'h23, 8'h26, 8'h27, 8'h28, 8'h29, 8'h2B, 8'h2E, 8'h2F,
            8'h30, 8'h31, 8'h33, 8'h36, 8'h37, 8'h38, 8'h39, 8'h3B, 8'h3E, 8'h3F,
            8'h40, 8'h41, 8'h42, 8'h43, 8'h45, 8'h46, 8'h47, 8'h48, 8'h49, 8'h4A, 8'h4B, 8'h4D, 8'h4E, 8'h4F,
            8'h50, 8'h51, 8'h52, 8'h53, 8'h55, 8'h56, 8'h57, 8'h58, 8'h59, 8'h5A, 8'h5B, 8'h5D, 8'h5E, 8'h5F,
            8'h60, 8'h61, 8'h62, 8'h63, 8'h65, 8'h66, 8'h67, 8'h68, 8'h69, 8'h6A, 8'h6B, 8'h6D, 8'h6E, 8'h6F,
            8'h70, 8'h71, 8'h72, 8'h73, 8'h75, 8'h76, 8'h77,
            8'h80, 8'h81, 8'h82, 8'h83, 8'h84, 8'h86, 8'h87, 8'h88, 8'h89, 8'h8A, 8'h8B, 8'h8C, 8'h8E, 8'h8F,
            8'h90, 8'h91, 8'h92, 8'h93, 8'h94, 8'h98, 8'h99, 8'h9A, 8'h9B,
            8'hA0, 8'hA1, 8'hA2, 8'hA3, 8'hA4, 8'hA5, 8'hA6, 8'hA7, 8'hA8, 8'hA9, 8'hAA, 8'hAB, 8'hAC, 8'hAD, 8'hAE, 8'hAF,
            8'hC8, 8'hC9, 8'hCA, 8'hCB, 8'hCC, 8'hCD,
            8'hDE, 8'hDF,
            8'hF4, 8'hF6, 8'hF7, 8'hF8, 8'hF9, 8'hFA, 8'hFF:
            begin
                need_opext <= 0;
                need_imm   <= 0;
                imm_size   <= 0;
            end

            // Opcodes with one 8-bit operand:
            8'h02, 8'h04, 8'h0A, 8'h0C,
            8'h12, 8'h14, 8'h1A, 8'h1C,
            8'h22, 8'h24, 8'h2A, 8'h2C,
            8'h32, 8'h34, 8'h3A, 8'h3C,
            8'h44, 8'h4C,
            8'h54, 8'h5C,
            8'h64, 8'h6C,
            8'h74, 8'h78, 8'h79, 8'h7A, 8'h7B, 8'h7D, 8'h7E, 8'h7F,
            8'h85, 8'h8D,
            8'h95, 8'h96, 8'h97, 8'h9C, 8'h9D, 8'h9E, 8'h9F,
            8'hB0, 8'hB1, 8'hB2, 8'hB3, 8'hB4, 8'hB5, 8'hB6, 8'hB7,
            8'hE0, 8'hE1, 8'hE2, 8'hE3, 8'hE4, 8'hE5, 8'hE6, 8'hE7,
            8'hF0, 8'hF1, 8'hF5, 8'hFC, 8'hFD:
            begin
                need_opext <= 0;
                need_imm   <= 1;
                imm_size   <= 0;
            end

            // Opcodes with two 8-bit operands:
            8'h05, 8'h0D,
            8'h15, 8'h1D,
            8'h25, 8'h2D,
            8'h35, 8'h3D,
            8'hB8, 8'hB9, 8'hBA, 8'hBB, 8'hBC, 8'hBD, 8'hBE, 8'hBF,
            8'hC0, 8'hC1, 8'hC2, 8'hC3, 8'hC4, 8'hC5, 8'hC6, 8'hC7,
            8'hD0, 8'hD1, 8'hD2, 8'hD3, 8'hD4, 8'hD5, 8'hD6, 8'hD7, 8'hD8, 8'hD9, 8'hDA, 8'hDB, 8'hDC, 8'hDD,
            8'hE8, 8'hE9, 8'hEA, 8'hEB, 8'hEC, 8'hED, 8'hEE, 8'hEF,
            8'hF2, 8'hF3, 8'hFB:
            begin
                need_opext <= 0;
                need_imm   <= 1;
                imm_size   <= 1;
            end

            8'hCE, 8'hCF:
            begin
                need_opext <= 1;
                need_imm   <= need_imm_ext;
                imm_size   <= imm_size_ext;
            end

            default:
            begin
                error_temp <= 1;
                need_opext <= 0;
                need_imm   <= 0;
                imm_size   <= 0;
            end
        endcase
    end

endmodule
