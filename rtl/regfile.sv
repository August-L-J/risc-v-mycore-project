// 32×32 位寄存器堆：两个组合读口，一个时钟上升沿写口，x0 恒为 0
module regfile (
  input  logic        clk,
  input  logic [4:0]  raddr1,
  output logic [31:0] rdata1,
  input  logic [4:0]  raddr2,
  output logic [31:0] rdata2,
  input  logic        we,
  input  logic [4:0]  waddr,
  input  logic [31:0] wdata
);

  // (L3): 存储阵列、写逻辑、两个读口，要求见讲义第五节
  logic [31:0] rf [1:31]; // 32位×31个 寄存器堆

  // 写逻辑，跳过x0的寄存器写入，因为根本就没有定义出来x0寄存器
  always_ff @(posedge clk)begin
    if (we != 1'b0 && waddr != 5'b0)begin    //跳过x0的寄存器写入（相当于：x0寄存器什么也不做），其他寄存器照常写。
          rf[waddr] <= wdata;
        end
    end


  // 读口逻辑，对x0特殊处理，对于register file只设置出31个寄存器，读写x0的时候都挡住

  assign rdata1 = (raddr1 == 5'b0) ? 32'b0 : rf[raddr1];
  assign rdata2 = (raddr2 == 5'b0) ? 32'b0 : rf[raddr2];


endmodule
