#!/usr/bin/env python3
"""把 objcopy -O binary 生成的二进制镜像转成 $readmemh 能读的文本：每行一个 32 位字（小端组装）。

用法：bin2hex.py 输入.bin 输出.hex
镜像从链接地址 0x80000000 开始，第 i 行就是地址 0x80000000 + 4*i 的那个字。
"""
import struct
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    data = open(sys.argv[1], "rb").read()
    data += b"\0" * (-len(data) % 4)
    if len(data) > 64 * 1024:
        print(f"镜像 {len(data)} 字节，超过仿真存储器的 64 KiB", file=sys.stderr)
        return 1
    with open(sys.argv[2], "w") as f:
        for i in range(0, len(data), 4):
            f.write("%08x\n" % struct.unpack_from("<I", data, i))
    return 0


if __name__ == "__main__":
    sys.exit(main())
