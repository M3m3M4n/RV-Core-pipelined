_start:
    slti	sp,zero,1    # 00: 00102113 
    slli	sp,sp,0x1d   # 04: 01d11113  
    addi	s0,sp,128    # 08: 02010413
    addi	a5,zero,-8   # 0c: ff800793  
    sw      a5,-28(s0)   # 10: fef42223  
    addi	a5,zero,-4   # 14: ffc00793  
    sw	    a5,-32(s0)   # 18: fef42023  
    lui	    a5,0x30000   # 1c: 300007b7  // investigate
    sw	    a5,-20(s0)   # 20: fef42623  // investigate
    lui	    a5,0x30009   # 24: 300097b7  
    addi	a5,a5,1536   # 28: 60078793  
    sw	    a5,-36(s0)   # 2c: fcf42e23  
    lui	    a5,0x30009   # 30: 300097b7  
    addi	a5,a5,1540   # 34: 60478793  
    sw	    a5,-40(s0)   # 38: fcf42c23  
    sb	    zero,-21(s0) # 3c: fe0405a3    
_jmp0:
    lw	    a5,-28(s0)    #  40: fe442783     
    lw	    a4,0(a5)      #  44: 0007a703   
    lw	    a5,-32(s0)    #  48: fe042783     
    sw	    a4,0(a5)      #  4c: 00e7a023   
    lbu	    a5,-21(s0)    #  50: feb44783     
    beq	    a5,zero,_jmp1 #  54: 00078a63        
    lw	    a5,-20(s0)    #  58: fec42783     
    li	    a4,-1         #  5c: fff00713
    sw	    a4,0(a5)      #  60: 00e7a023   
    jal	    zero,_jmp2    #  64: 00c0006f     
_jmp1:
    lw	    a5,-20(s0)    #  68: fec42783
    sw	    zero,0(a5)    #  6c: 0007a023
_jmp2:
    lw	a5,-20(s0)        # 70: fec42783
    addi	a5,a5,4       # 74: 00478793 
    sw	a5,-20(s0)        # 78: fef42623
    lw	a4,-20(s0)        # 7c: fec42703
    lui	a5,0x30009        # 80: 300097b7
    addi	a5,a5,1535    # 84: 5ff78793    
    bgeu	a5,a4,_jmp0   # 88: fae7fce3     
    lui	a5,0x30000        # 8c: 300007b7
    sw	a5,-20(s0)        # 90: fef42623
    lbu	a5,-21(s0)        # 94: feb44783
    sltiu	a5,a5,1       # 98: 0017b793 
    andi	a5,a5,255     # 9c: 0ff7f793   
    sb	a5,-21(s0)        # a0: fef405a3
    jal	zero,_jmp0        # a4: f9dff06f
