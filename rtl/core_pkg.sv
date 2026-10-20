// mycore 全局类型定义：ALU 运算码等，L3～L5 的模块共用
package core_pkg;

  // 编码刻意对齐 {inst[30], funct3}，L4 译码 R 型时可直接拼出来
  typedef enum logic [3:0] {
    ALU_ADD  = 4'b0_000,
    ALU_SUB  = 4'b1_000,
    ALU_SLL  = 4'b0_001,
    ALU_SLT  = 4'b0_010,
    ALU_SLTU = 4'b0_011,
    ALU_XOR  = 4'b0_100,
    ALU_SRL  = 4'b0_101,
    ALU_SRA  = 4'b1_101,
    ALU_OR   = 4'b0_110,
    ALU_AND  = 4'b0_111
  } alu_op_e;

  // 立即数格式：imm_gen 按它选拼法（L4）
  typedef enum logic [2:0] {
    IMM_I = 3'd0,
    IMM_S = 3'd1,
    IMM_B = 3'd2,
    IMM_U = 3'd3,
    IMM_J = 3'd4
  } imm_sel_e;

  // ALU A 端来源（L2 的 MuxA）
  typedef enum logic [1:0] {
    A_RS1  = 2'd0,
    A_PC   = 2'd1,
    A_ZERO = 2'd2
  } alu_a_sel_e;

  // ALU B 端来源（L2 的 MuxB）
  typedef enum logic {
    B_RS2 = 1'b0,
    B_IMM = 1'b1
  } alu_b_sel_e;

  // 写回来源（L2 的写回选择器）
  typedef enum logic [1:0] {
    WB_ALU = 2'd0,
    WB_MEM = 2'd1,
    WB_PC4 = 2'd2
  } wb_sel_e;

endpackage
