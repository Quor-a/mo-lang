#!/usr/bin/env python3
"""
a64dis —— aarch64 指令解码器，**独立实现**，只用于对拍

它的存在理由：examples/a64as.mo 是编码器，用它自己验证自己等于没验证。
本脚本按 ARM ARM 的字段布局**反向**把 32 位指令字解回助记符与操作数，
再与汇编源码对照 —— 字段错位、移位写错、立即数截断，都能在这里现形。

用法：python3 tools/a64dis.py <elf> <insn_count>
"""
import struct, sys
d=open(sys.argv[1],'rb').read()
NC=int(sys.argv[2]) if len(sys.argv)>2 else 95
BASE=0x40000000
def sgn(v,b):
    if v & (1<<(b-1)): v -= (1<<b)
    return v
names={31:'sp'}
def R(r): return names.get(r, 'x%d'%r)
lines=[]
for k in range(NC):
    w=struct.unpack_from('<I', d, 120+k*4)[0]
    a=BASE+k*4
    t='?%08x'%w
    if (w & 0xFF800000)==0xD2800000:
        hw=(w>>21)&3; imm=(w>>5)&0xFFFF; rd=w&31
        t='movz %s, #0x%x, lsl #%d'%(R(rd),imm,hw*16)
    elif (w & 0xFF800000)==0xF2800000:
        hw=(w>>21)&3; imm=(w>>5)&0xFFFF; rd=w&31
        t='movk %s, #0x%x, lsl #%d'%(R(rd),imm,hw*16)
    elif (w & 0xFF000000)==0x91000000:
        imm=(w>>10)&0xFFF; rn=(w>>5)&31; rd=w&31
        t='add %s, %s, #%d'%(R(rd),R(rn),imm)
    elif (w & 0xFF000000)==0xD1000000:
        imm=(w>>10)&0xFFF; rn=(w>>5)&31; rd=w&31
        t='sub %s, %s, #%d'%(R(rd),R(rn),imm)
    elif (w & 0xFF000000)==0x8B000000:
        rm=(w>>16)&31; rn=(w>>5)&31; rd=w&31
        t='add %s, %s, %s'%(R(rd),R(rn),R(rm))
    elif (w & 0xFF000000)==0xCB000000:
        rm=(w>>16)&31; rn=(w>>5)&31; rd=w&31
        t='sub %s, %s, %s'%(R(rd),R(rn),R(rm))
    elif (w & 0xFF000000)==0xF1000000:
        imm=(w>>10)&0xFFF; rn=(w>>5)&31; rd=w&31
        t='cmp %s, #%d'%(R(rn),imm) if rd==31 else 'subs %s,%s,#%d'%(R(rd),R(rn),imm)
    elif (w & 0xFF000000)==0xEB000000:
        rm=(w>>16)&31; rn=(w>>5)&31; rd=w&31
        t='cmp %s, %s'%(R(rn),R(rm)) if rd==31 else 'subs %s,%s,%s'%(R(rd),R(rn),R(rm))
    elif (w & 0xFC000000)==0x14000000:
        off=sgn(w&0x3FFFFFF,26)*4
        t='b 0x%x'%(a+off)
    elif (w & 0xFC000000)==0x94000000:
        off=sgn(w&0x3FFFFFF,26)*4
        t='bl 0x%x'%(a+off)
    elif (w & 0xFF000010)==0x54000000:
        cond=['eq','ne','cs','cc','mi','pl','vs','vc','hi','ls','ge','lt','gt','le','al','nv'][w&15]
        off=sgn((w>>5)&0x7FFFF,19)*4
        t='b.%s 0x%x'%(cond,a+off)
    elif (w & 0xFFC00000)==0xF9400000:
        imm=((w>>10)&0xFFF)*8; rn=(w>>5)&31; rd=w&31
        t='ldr %s, [%s, #%d]'%(R(rd),R(rn),imm)
    elif (w & 0xFFC00000)==0xF9000000:
        imm=((w>>10)&0xFFF)*8; rn=(w>>5)&31; rt=w&31
        t='str %s, [%s, #%d]'%(R(rt),R(rn),imm)
    elif (w & 0xFFC00000)==0x39400000:
        imm=(w>>10)&0xFFF; rn=(w>>5)&31; rd=w&31
        t='ldrb w%d, [%s, #%d]'%(rd,R(rn),imm)
    elif (w & 0xFFC00000)==0x39000000:
        imm=(w>>10)&0xFFF; rn=(w>>5)&31; rt=w&31
        t='strb w%d, [%s, #%d]'%(rt,R(rn),imm)
    elif (w & 0xFF000000)==0xAA000000:
        rm=(w>>16)&31; rn=(w>>5)&31; rd=w&31
        t='orr %s, %s, %s'%(R(rd),R(rn),R(rm))
    elif (w & 0xFF000000)==0x9B000000:
        rm=(w>>16)&31; rn=(w>>5)&31; rd=w&31
        t='mul %s, %s, %s'%(R(rd),R(rn),R(rm))
    elif w==0xD65F03C0: t='ret'
    elif w==0xD503207F: t='wfi'
    elif w==0xD503201F: t='nop'
    elif w==0xD4000001: t='svc #0'
    elif (w & 0xFFFFFC1F)==0xD61F0000:
        t='br %s'%R((w>>5)&31)
    lines.append('%3d  0x%08x  %-28s' % (k, a, t))
print('\n'.join(lines))
bad = [l for l in lines if '?' in l]
if bad:
    import sys
    sys.stderr.write("DECODE-FAIL: %d 条指令无法识别\n" % len(bad))
    sys.exit(1)
