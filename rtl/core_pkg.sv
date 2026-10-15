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

endpackage
