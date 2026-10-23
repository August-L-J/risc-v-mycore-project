// 访存单元（load/store unit）：在 CPU 和按字（32 位）组织的数据存储器之间做字节对齐
//   store：把 rs2 的低 1/2/4 字节摆到这个字里正确的位置，并给出字节写使能
//   load ：从读出的整个字里挑出要的字节，再做符号扩展或零扩展
module lsu (
  input  logic [31:0] addr,        // ALU 算出的字节地址 rs1 + imm
  input  logic [2:0]  mem_size,    // = funct3：000 b，001 h，010 w，100 bu，101 hu
  input  logic        mem_we,      // 这是一条 store
  input  logic [31:0] store_data,  // rs2 的值

  output logic [31:0] dmem_addr,   // 送给存储器的字地址（低 2 位清零）
  output logic [31:0] dmem_wdata,  // 摆好位置的写数据
  output logic [3:0]  dmem_wmask,  // 字节写使能，bit i 对应 wdata[8i+7:8i]；不写时为 0

  input  logic [31:0] dmem_rdata,  // 存储器读出的整个字
  output logic [31:0] load_data    // 扩展好的 32 位结果，送写回选择器
);


  // 地址：一行 assign，把 addr 的低 2 位换成 0。

  assign dmem_addr = {addr[31:2],2'b00};

  /*
  store：一个 always_comb，开头给 wdata、wmask 默认值 0。只有 mem_we = 1 时才按 mem_size 设置：

    wmask：sb 是 4'b0001，sh 是 4'b0011，再左移 off 位；sw 是 4'b1111。
    wdata：最简单的办法是把要写的字节复制满整个字，例如 sb 写成 {4{store_data[7:0]}}。
    不管 off 是几，正确的字节都已经在正确的位置上了，wmask 会挑出那一个。想一想 sh 怎么写。

  */



  /*
  store：里面有sb,sh,sw三种情况，需要控制信号mem_we使能，需要meme_size（也就是funct3）来判断是哪种情况，
  输入：需要store_data写数据，输出：dmem_wdata和dmem_wmask
  */  

  always_comb begin

    // 先把需要输出的赋值的两个量初始化为0，因为是组合逻辑，后面写好case防止出现latch
    dmem_wdata = 32'b0;
    dmem_wmask = 4'b0;

    if (mem_we) begin

      unique case (mem_size)

        3'b000 : begin // sb rs2, imm(rs1)  ，M[Reg[rs1] + imm] = Reg[rs2] 的低 1 字节
/*
操作：算出来Reg[rs1]+imm的地址等于addr输入lsu，
我们需要寻找要写入的那个Byte的所在的Word，然后由于DMEM是32位的，相当于1Word，4Byte，需要把addr的低2位清零得到dmem_addr，
这样就确定要写入的Byte的所在word了，然后addr[1:0]就是addr的低2位，相当于是一个Word的4个Byte的寻址Sel，比如：ABCD，要找其中一个Byte

那么 dmem_wmask进行一个addr[1:0]的左移操作，就可以明确知道要写入的字节的所在的位置了。
要写入的数据就是Reg[rs2]的低1字节，就是低8位，还需要 把这个低8位复制4次，形成一个32位的写入数据dmem_wdata，
这样就可以通过dmem_wmask来选择要写入的字节了。
*/
          dmem_wmask = 4'b0001 << addr[1:0]; // sb指令的字节使能
          dmem_wdata = {4{store_data[7:0]}}; // sb指令的写数据
        end

        3'b001 : begin // sh rs2, imm(rs1)  , M[Reg[rs1] + imm] = Reg[rs2] 的低 2 字节

          dmem_wmask = 4'b0011 << addr[1:0]; // sh指令的字节使能
          dmem_wdata = {2{store_data[15:0]}}; // sh指令的写数据
        
        end

        3'b010 : begin  // sw rs2, imm(rs1)  , M[Reg[rs1] + imm] = rs2  ，一整个Word，不需要移位了

          dmem_wmask = 4'b1111; // sw的字节使能
          dmem_wdata = store_data; // sw的写数据

        end

        default : begin

          dmem_wmask = 4'b0000; // 默认不写，全是0
          dmem_wdata = 32'b0; // 默认写数据为0
        end

      endcase
      
    end
  
  
  end


  /*
  load：另一个 always_comb。先用 +: 取出偏移处的字节和半字，再按 mem_size 扩展。扩展的写法就是 SV 速成第 6 节的拼接。
  规律：偏移 off 的字节在 [8·off+7 : 8·off]。
  SV 里写这种“起点可变、宽度固定”的切片用 `+:`的操作：x[8*off +: 8] 表示从第 8·off 位开始、往上取 8 位。
  这是 SV 速成没讲到的一个写法，lsu 里很好用。

  mem_size 的 bit2 区分有无符号（lb = 000，lbu = 100），低 2 位区分宽度。
  可以直接 case 完整的 3 位，也可以分开用。
  */


  /*
  这里是load指令，有 lb,lh,lw,lbu,lhu五种情况，都是从dmem_rdata中取出对应的字节或半字，
  然后进行符号扩展或零扩展，最后赋值给load_data

  输入：需要 addr，mem_size，dmem_rdata
  输出：load_data  
  
  */
  always_comb begin

    unique case (mem_size)

      3'b000 : begin // lb rd, imm(rs1) , Reg[rd] = M[Reg[rs1] + imm] 的 1 字节，符号扩展

/*
一样的道理，把addr的低两位归零就可以确定好需要处理的Byte所在的Word在哪里了，
再根据addr的低两位来确定要读取的Byte这一位字节在Word里面的位置，
然后通过 MEM[8*offset +: 8]就可以每次8位地选择了，
比如：MEM[0 +: 8]，MEM[8 +: 8]，MEM[16 +: 8]，MEM[24 +: 8]，得到MEM[7:0],MEM[15:8],MEM[23:16],MEM[31:24]
把找到的低8位放好，然后抓住最高位进行24次复制进行符号拓展
*/

        load_data = { { 24{ dmem_rdata[8*addr[1:0] + 7] } } , dmem_rdata[8*addr[1:0] +: 8] };

      end

      3'b001 : begin // lh rd, imm(rs1) ,  Reg[rd] = M[Reg[rs1] + imm] 的 2 字节，符号拓展

        load_data = { {16{ dmem_rdata[8*addr[1:0] + 15] }} , dmem_rdata[8*addr[1:0] +: 16]   };

      end

      3'b010 : begin // lw rd, imm(rs1),   Reg[rd] = M[Reg[rs1] + imm] 的 4 字节，直接取出来

        load_data = dmem_rdata;
      end

      3'b100 : begin // lbu rd, imm(rs1) , Reg[rd] = M[Reg[rs1] + imm] 的 1 字节，零拓展

        load_data = { 24'b0, dmem_rdata[8*addr[1:0] +: 8]   };
      end

      3'b101 : begin // lhu rd, imm(rs1) ,  Reg[rd] = M[Reg[rs1] + imm] 的 2字节，零拓展

        load_data = {16'b0 , dmem_rdata[8*addr[1:0] +: 16]   };

      end

      default : begin
        load_data = 32'b0; // 默认输出0
      end


    endcase

  end


endmodule
