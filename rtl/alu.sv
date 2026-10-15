// 纯组合 ALU：y = a op b
module alu
  import core_pkg::*;
(
  input  alu_op_e     op,
  input  logic [31:0] a,
  input  logic [31:0] b,
  output logic [31:0] y
);

  always_comb begin
    unique case (op)
      ALU_ADD : y = a + b;
      ALU_SUB : y = a - b;
      ALU_SLL : y = a << b[4:0];
      ALU_SLT : y = $signed(a) < $signed(b) ? 32'd1 : 32'd0;
      ALU_SLTU : y = a < b ? 32'd1 : 32'd0;
      ALU_XOR : y = a ^ b;
      ALU_SRL : y = a >> b[4:0];
      ALU_SRA : y = $signed(a) >>> b[4:0];
      ALU_OR : y = a | b;
      ALU_AND : y = a & b;
      default : y = 32'd0;
    endcase
  end

endmodule





