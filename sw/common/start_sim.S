    # 仿真启动代码：设好栈指针，调用 main，main 的返回值留在 a0，然后 ebreak 通知测试平台结束
    # 和 sw/hello/start.S 的唯一区别：结尾用 ebreak 代替死循环
    .section .text.init
    .globl _start
_start:
    la   sp, _stack_top
    call main
    ebreak
