module DataMaskDecoder (
    // Outputs go to data mem block
    input  logic [2:0] funct3,
    output logic [1:0] mask_type,// 00: byte, 01: halfword, 10: word
    output logic       ext_type  // 0: signed extension, 1: zero extension
);
    // Is this pure coincidence?
    // Put here incase something changes. No invalid funct3 guard
    assign mask_type = funct3[1:0];
    assign ext_type  = funct3[2];

endmodule
