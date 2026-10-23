// 单周期 RV32I 核：PC、译码、寄存器堆、立即数、ALU、分支比较、访存对齐、写回、下一 PC
// 存储器不在核内，由外面的 soc_top 连接（指令口只读，数据口读写）
module core_top
  import core_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,          // 异步低有效复位，PC 复位到 RESET_PC

  // 指令存储器（组合读）
  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,

  // 数据存储器（组合读，时钟上升沿按字节写）
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wdata,
  output logic [3:0]  dmem_wmask,
  input  logic [31:0] dmem_rdata,

  // 仿真用：本周期这条指令的情况，测试平台据此停机、打印执行轨迹
  output logic [31:0] dbg_pc,         // 当前指令的 PC
  output logic [31:0] dbg_inst,       // 当前指令
  output logic        dbg_rf_we,      // 本周期是否写寄存器
  output logic [4:0]  dbg_rd,
  output logic [31:0] dbg_wdata,      // 写回 rd 的值
  output logic        dbg_halt,       // ebreak
  output logic        dbg_illegal     // 非法指令
);

  localparam logic [31:0] RESET_PC = 32'h8000_0000;




/*

内部信号先声明

建议先把所有内部信号一次声明清楚，名字和 L2 讲义保持一致，后面连线时不会乱：
类别	信号
PC	pc_q（当前 PC）、pc_d（下一 PC）、pc4
指令字段	inst（= imem_rdata），rs1、rs2、rd 的地址直接取 inst 的位
译码器输出	和 decoder 端口同名同类型：rf_we、imm_sel（imm_sel_e）、alu_a_sel、alu_b_sel、alu_op、wb_sel、mem_we、mem_re、mem_size、is_br、is_jal、is_jalr、halt、illegal
数据	rs1_v、rs2_v（寄存器堆读出）、imm、alu_a、alu_b、alu_y、load_data、wb_data（写回 rd 的值）
跳转	br_taken、pc_sel

枚举信号建议用枚举类型声明（例如 alu_a_sel_e alu_a_sel;）。实测：用普通 logic [1:0] 去接 decoder 的枚举输出不会报错，但之后写 case (alu_a_sel) A_PC: ... 时就成了“拿 logic 和枚举比较”，波形里也看不到名字。反过来，把 logic 赋给枚举类型的输入会直接报 ENUMVALUE 错（L4 讲过）。


*/


logic [31:0] pc_q, pc_d, pc4;  

logic [31:0] inst, rs1_v, rs2_v, imm , alu_a, alu_b, alu_y, load_data, wb_data; // 这里的imm 直接就是计算imm的32位结果了。

logic [4:0] rs1 ,rs2 ,rd;
logic [2:0] mem_size;

// 枚举变量的定义
imm_sel_e imm_sel;
alu_a_sel_e alu_a_sel;
alu_b_sel_e alu_b_sel;
alu_op_e alu_op;
wb_sel_e wb_sel;

logic rf_we, mem_we , mem_re, is_br, is_jal ,is_jalr , br_taken, pc_sel;

logic halt , illegal;


logic [3:0] lsu_wmask; // lsu 原始输出的字节写使能，还没过commit_ok的门控
logic decoder_rf_we; // 译码器输出的原始寄存器堆写使能，还没过commit_ok的门控
logic commit_ok;  // 这条指令是否允许改状态， 这三行用来解决 wmask 和 rf_we 遇到非法指令的时候，
                   // 保证在非法指令的情况下，wmask 不会影响到数据存储器，rf_we 不会影响到寄存器堆


  regfile u_regfile(

    .clk      (clk),
    .raddr1   (rs1),
    .rdata1   (rs1_v),
    .raddr2   (rs2),
    .rdata2   (rs2_v),
    .we       (rf_we),
    .waddr    (rd),
    .wdata    (wb_data)

  );


  imm_gen u_imm_gen(

    .inst     (inst),
    .imm_sel  (imm_sel),
    .imm      (imm)
  );


  alu u_alu(

    .op       (alu_op),
    .a        (alu_a),
    .b        (alu_b),
    .y        (alu_y)
  );

 

  decoder u_decoder(

    .inst      (inst),

    .rf_we     (decoder_rf_we),
    .imm_sel   (imm_sel),

    .alu_a_sel (alu_a_sel),
    .alu_b_sel (alu_b_sel),
    .alu_op    (alu_op),

    .wb_sel    (wb_sel),

    .mem_we    (mem_we),
    .mem_re    (mem_re),
    .mem_size  (mem_size),

    .is_br     (is_br),
    .is_jal    (is_jal),
    .is_jalr   (is_jalr),
    .halt      (halt),
    .illegal   (illegal)
  );


  lsu u_lsu(
    .addr         (alu_y),
    .mem_size     (mem_size),
    .mem_we       (mem_we),

    .store_data   (rs2_v),
    .dmem_addr    (dmem_addr),
    .dmem_wdata   (dmem_wdata),
    .dmem_wmask   (lsu_wmask),  // 先接 lsu 的输出，后面再和非法指令、ebreak 冻结 PC 的信号相与，得到最终的 dmem_wmask

    .dmem_rdata   (dmem_rdata),
    .load_data    (load_data)
  );



assign commit_ok = ~illegal & ~halt; // 这条指令是否允许改状态， 用来解决 wmask 和 rf_we 遇到非法指令的时候，
                                   // 保证在非法指令的情况下，wmask 不会影响到数据存储器 , rf_we 不会影响到寄存器堆

assign dmem_wmask = lsu_wmask & {4{commit_ok}}; // 只有 commit_ok 为 1 时，才允许写数据存储器
assign rf_we = decoder_rf_we & commit_ok; // 只有 commit_ok 为 1 时，才允许写寄存器堆


// 处理PC部分

always_comb begin

  imem_addr = pc_q; //  取指令地址,最一开始的

  pc4 = pc_q + 32'd4;

  pc_sel = is_jal | is_jalr | (is_br & br_taken);

  if( commit_ok == 1'b1 ) begin        // 处理非法指令

    pc_d = pc_sel ? {alu_y[31:1], 1'b0 } : pc4; // 选择下一 PC  ，由于jalr的目标需要最低位清零，所以这是alu_y的跳转设计的特殊构造
    // pc_d = pc_sel ?  alu_y: pc4; // 选择下一 PC  ，由于jalr的目标需要最低位清零，所以这是alu_y的跳转设计的特殊构造

  
  end
/*
对于 jal和分支而言，跳转的目标都是 pc_q+imm
pc_q： 复位值是 0x8000_0000。之后每一拍要么 +4，要么跳到一个最低位被清零的目标，所以 pc_q 永远是偶数。

而对于imm而言：
IMM_B : imm = { {20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0 };
IMM_J : imm = { {12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0 };

两种立即数的最低位都是硬拼进去的 1'b0。B 型和 J 型的指令编码里根本没有 imm[0] 这一位，规范规定它恒为 0（L1、L4 讲过），所以 imm 也一定是偶数。
偶数加偶数还是偶数，所以 alu_y[0] 必然是 0。{alu_y[31:1], 1'b0} 把 0 换成 0，结果和 alu_y 一模一样。

而对于jalr而言会出现奇数的可能性：
jalr 的目标是 rs1_v + imm，用的是 I 型立即数。

rs1_v： 是寄存器里的任意值，可能是 奇数 。
imm： I 型立即数是 inst[31:20] 符号扩展得到的，imm[0] 就是 inst[20]，可以是 1。
所以只有 jalr 的目标可能是奇数，规范才要求清零。

*/


  else begin

    pc_d = pc_q; // ebreak 或非法指令时冻结 PC
  end

end

// 时序更新PC寄存器
always_ff @(posedge clk or negedge rst_n) begin

  if(rst_n == 1'b0)begin
    pc_q <= RESET_PC;
  end
  else begin
    pc_q <= pc_d;
  end
end


assign dbg_pc = pc_q;
assign dbg_inst = inst;
assign dbg_rf_we = rf_we; // 这条指令是否允许改状态
assign dbg_rd = inst[11:7];
assign dbg_wdata = wb_data;
assign dbg_halt = halt;
assign dbg_illegal = illegal;




assign inst = imem_rdata;

assign rs1 = imem_rdata[19:15];
assign rs2 = imem_rdata[24:20];
assign rd  = imem_rdata[11: 7];

// 



// 处理ALU_A的选择
always_comb begin

  unique case(alu_a_sel)

    A_RS1 : alu_a = rs1_v;
    A_PC  : alu_a = pc_q;
    A_ZERO: alu_a = 32'b0;

    default : alu_a = 32'b0; // 默认输出0

  endcase

end

// 处理ALU_B的选择

assign alu_b = (alu_b_sel == B_RS2) ? rs2_v : imm;



/*

处理分支比较器 BrCmp

汇编写法	funct3	功能	
beq rs1, rs2, imm	000	rs1 == rs2 时 PC = PC + imm	
bne rs1, rs2, imm	001	rs1 != rs2 时 PC = PC + imm	
blt rs1, rs2, imm	100	rs1 < rs2（有符号）时 PC = PC + imm	
bge rs1, rs2, imm	101	rs1 >= rs2（有符号）时 PC = PC + imm	
bltu rs1, rs2, imm	110	rs1 < rs2（无符号）时 PC = PC + imm	
bgeu rs1, rs2, imm	111	rs1 >= rs2（无符号）时 PC = PC + imm	

*/


always_comb begin

  unique case(inst[14:12])

    3'b000 : br_taken = (rs1_v == rs2_v); // beq
    3'b001 : br_taken = (rs1_v != rs2_v); // bne
    3'b100 : br_taken = ($signed(rs1_v) < $signed(rs2_v)); // blt
    3'b101 : br_taken = ($signed(rs1_v) >= $signed(rs2_v)); // bge
    3'b110 : br_taken = (rs1_v < rs2_v); // bltu
    3'b111 : br_taken = (rs1_v >= rs2_v); // bgeu

    default : br_taken = 1'b0; // 非分支指令，默认不跳转


  endcase

end



// WB写回选择器 

always_comb begin

  unique case(wb_sel)
  
    WB_ALU : wb_data = alu_y;
    WB_MEM : wb_data = load_data;
    WB_PC4 : wb_data = pc4;

    default : wb_data = 32'b0; // 默认输出0  
  endcase

end



endmodule
