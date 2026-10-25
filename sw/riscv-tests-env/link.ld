/* riscv-tests 的链接脚本：代码从 0x80000000 开始（和 mem.sv 的 BASE 一致），
   数据段放到下一个 4 KiB 边界。整个程序要放得进 64 KiB 的仿真存储器。 */
OUTPUT_ARCH( "riscv" )
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  .text.init : { *(.text.init) }
  .text : { *(.text) }
  . = ALIGN(0x1000);
  .data : { *(.data) }
  .bss : { *(.bss) }
  _end = .;
}
