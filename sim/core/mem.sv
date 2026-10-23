// 仿真用存储器：一块 64 KiB 的 RAM，同时给指令口和数据口用（冯·诺依曼结构，和 hello 的链接脚本一致）
//   基地址 0x8000_0000，按 32 位字组织，共 16384 个字
//   指令口、数据口都是组合读；数据口在时钟上升沿按 wmask 写字节
//   超出范围的访问：读回 0，写被忽略，并拉高 *_oob 供测试平台报错
// 程序由测试平台用 +prog=xxx.hex 指定，$readmemh 读入（每行一个 32 位字）
module mem #(
  parameter logic [31:0] BASE  = 32'h8000_0000,
  parameter int          WORDS = 16384
) (
  input  logic        clk,

  input  logic [31:0] imem_addr,
  output logic [31:0] imem_rdata,
  output logic        imem_oob,

  input  logic [31:0] dmem_addr,
  input  logic [31:0] dmem_wdata,
  input  logic [3:0]  dmem_wmask,
  output logic [31:0] dmem_rdata,
  output logic        dmem_oob
);

  localparam int AW = $clog2(WORDS);

  logic [31:0] ram [WORDS];

  initial begin
    string path;
    for (int i = 0; i < WORDS; i++) ram[i] = '0;
    if ($value$plusargs("prog=%s", path)) $readmemh(path, ram);
  end

  logic [31:0] ioff, doff;
  assign ioff = imem_addr - BASE;
  assign doff = dmem_addr - BASE;

  assign imem_oob   = ioff[31:2] >= 30'(WORDS);
  assign dmem_oob   = (doff[31:2] >= 30'(WORDS)) && (dmem_wmask != '0);
  assign imem_rdata = imem_oob ? '0 : ram[ioff[AW+1:2]];
  assign dmem_rdata = (doff[31:2] >= 30'(WORDS)) ? '0 : ram[doff[AW+1:2]];

  always_ff @(posedge clk) begin
    if (doff[31:2] < 30'(WORDS)) begin
      for (int i = 0; i < 4; i++)
        if (dmem_wmask[i]) ram[doff[AW+1:2]][8*i +: 8] <= dmem_wdata[8*i +: 8];
    end
  end

endmodule
