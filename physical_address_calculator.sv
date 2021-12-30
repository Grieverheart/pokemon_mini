module physical_address_calculator
(
    input [15:0] registers[0:7],
    input [15:0] segment_registers[0:3],
    input [2:0] segment_override, // High bit = enable/disable override.

    input [15:0] displacement,
    input [2:0] rm,
    input [1:0] mod,

    output [19:0] physical_address
);
    reg [3:0] base;
    reg [3:0] index;
    reg [1:0] seg;

    // @note: The high bit of the base and index registers is set when the
    // register is not used in the effective address calculation.
    always_comb
    begin
        case (rm)
            3'b000:
            begin
                base  = 4'b0011;
                index = 4'b0110;
                seg   = 2'b11;
            end
            3'b001:
            begin
                base  = 4'b0011;
                index = 4'b0111;
                seg   = 2'b11;
            end
            3'b010:
            begin
                base  = 4'b0101;
                index = 4'b0110;
                seg   = 2'b10;
            end
            3'b011:
            begin
                base  = 4'b0101;
                index = 4'b0111;
                seg   = 2'b10;
            end
            3'b100:
            begin
                base  = 4'b1100;
                index = 4'b0110;
                seg   = 2'b11;
            end
            3'b101:
            begin
                base  = 4'b1100;
                index = 4'b0111;
                seg   = 2'b00;
            end
            3'b110:
            begin
                base  = (mod != 0) ? 4'b0101 : 4'b1100;
                index = 4'b1100;
                seg   = (mod != 0) ? 2'b10 : 2'b11;
            end
            3'b111:
            begin
                base  = 4'b0011;
                index = 4'b1100;
                seg   = 2'b11;
            end
        endcase
    end

    wire [15:0] base_reg  = registers[base[2:0]];
    wire [15:0] index_reg = registers[index[2:0]];
    wire [15:0] seg_reg   = segment_override[2]? segment_registers[segment_override[1:0]]: segment_registers[seg];

    assign physical_address =
        {seg_reg, 4'd0} +
        (base[3]?  0: {4'd0, base_reg}) +
        (index[3]? 0: {4'd0, index_reg}) +
        (&mod?     {4'd0, displacement}: 0);

endmodule
