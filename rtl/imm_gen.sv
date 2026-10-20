// 立即数生成：按 imm_sel 从指令里取出立即数，统一符号扩展到 32 位
module imm_gen
  import core_pkg::*;
(
  input  logic [31:0] inst,
  input  imm_sel_e    imm_sel,
  output logic [31:0] imm
);



  always_comb begin
    unique case(imm_sel)
      IMM_I : imm = { {21{inst[31]}}, inst[30:20]};
      IMM_S : imm = { {21{inst[31]}}, inst[30:25] , inst[11:7] };
      IMM_B : imm = { {20{inst[31]}}, inst[7] , inst[30:25] , inst[11:8] , 1'b0};
      IMM_U : imm = { inst[31], inst[30:12], 12'b0 };
      IMM_J : imm = { {12{inst[31]}} , inst[19:12] , inst[20] , inst[30:21] , 1'b0 };
      default : imm = 32'b0; 
    endcase
  end

endmodule
