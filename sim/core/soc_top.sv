// 仿真顶层：core_top（你写的核）+ mem（仿真存储器）
// 测试平台只和这一层打交道
module soc_top (
  input  logic        clk,
  input  logic        rst_n,

  output logic [31:0] dbg_pc,
  output logic [31:0] dbg_inst,
  output logic        dbg_rf_we,
  output logic [4:0]  dbg_rd,
  output logic [31:0] dbg_wdata,
  output logic        dbg_halt,
  output logic        dbg_illegal,
  output logic        imem_oob,
  output logic        dmem_oob,
  output logic [31:0] dbg_dmem_addr,
  output logic [31:0] dbg_dmem_wdata,
  output logic [3:0]  dbg_dmem_wmask
);

  logic [31:0] imem_addr, imem_rdata;
  logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
  logic [3:0]  dmem_wmask;

  core_top u_core (
    .clk, .rst_n,
    .imem_addr, .imem_rdata,
    .dmem_addr, .dmem_wdata, .dmem_wmask, .dmem_rdata,
    .dbg_pc, .dbg_inst, .dbg_rf_we, .dbg_rd, .dbg_wdata, .dbg_halt, .dbg_illegal
  );

  mem u_mem (
    .clk,
    .imem_addr, .imem_rdata, .imem_oob,
    .dmem_addr, .dmem_wdata, .dmem_wmask, .dmem_rdata, .dmem_oob
  );

  assign dbg_dmem_addr  = dmem_addr;
  assign dbg_dmem_wdata = dmem_wdata;
  assign dbg_dmem_wmask = dmem_wmask;

endmodule
