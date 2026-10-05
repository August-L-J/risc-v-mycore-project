OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 64K
}

SECTIONS {
    .text : { *(.text.init) *(.text*) } > RAM
    .rodata : { *(.rodata*) *(.srodata*) } > RAM
    .data : { *(.data*) *(.sdata*) } > RAM
    .bss : { *(.bss*) *(.sbss*) *(COMMON) } > RAM
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
