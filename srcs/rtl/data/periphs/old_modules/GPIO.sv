module GPIO #(
    parameter SIZE_BIT = 32,
    // 32 bit address interface
    parameter START_ADDR = 32'hfffffff8, // enough space for 2 * SIZEBYTE, in and out regs
    localparam SIZEBYTE = SIZE_BIT >> 3  // div 8
)(
    // Bus interface
    input  logic              i_clk, i_rst,
    input  logic              i_addr_access,
    input  logic              i_we,
    input  logic [31:0]       i_addr, i_wd,
    input  logic [1:0]        i_mask_type,  // 00: byte, 01: halfword, 10: word
    output logic              o_ack,
    output logic              o_err,
    output logic [31:0]       o_rd,
    // GPIO interface
    // input  logic [7:0] i_gpio [SIZEBYTE - 1:0],
    // output logic [7:0] o_gpio [SIZEBYTE - 1:0]
    // Yosys does not support array in port list 
    input  logic [SIZE_BIT - 1:0] i_gpio,
    output logic [SIZE_BIT - 1:0] o_gpio
);

    // Byte addressible
    localparam ADDRWIDTH = $clog2((SIZEBYTE << 1) - 1); // SIZEBYTE * 2 for in and out regs

    // START_ADDR alignment check
    always_comb begin
        if (START_ADDR[ADDRWIDTH-1:0] != 'b0)
            $fatal("GPIO start address not aligned!");
    end

    // Delegate to memstage i_addr_access
    // Enable access after valid address check
    // logic _acc_en;
    // always_comb begin : addr_check
    //     _acc_en = (i_addr[31:ADDRWIDTH] == START_ADDR[31:ADDRWIDTH]) ? 1 : 0;
    // end

    // Phys access
    logic [7:0] _gpio_reg_in [SIZEBYTE - 1:0]; // in from phys pins
    logic [7:0] _gpio_reg_out[SIZEBYTE - 1:0]; // out to phys pins
    always_ff @(posedge i_clk) begin : gpio_input_buffer
        // _gpio_reg_in <= i_gpio;    // bus interface can read from _gpio_reg_in
        {_gpio_reg_in[SIZEBYTE - 1], _gpio_reg_in[SIZEBYTE - 2], _gpio_reg_in[SIZEBYTE - 3], _gpio_reg_in[SIZEBYTE - 4]} <= i_gpio;
    end
    // assign o_gpio = _gpio_reg_out; // bus interface can read / write from / to _gpio_reg_out
    assign o_gpio = {_gpio_reg_out[SIZEBYTE - 1], _gpio_reg_out[SIZEBYTE - 2], _gpio_reg_out[SIZEBYTE - 3], _gpio_reg_out[SIZEBYTE - 4]};
    // Mem access
    logic [ADDRWIDTH - 2:0] _addr;
    assign _addr = i_addr[ADDRWIDTH - 2:0];
    logic _reg_select;
    assign _reg_select = i_addr[ADDRWIDTH - 1];   // 0 = _gpio_reg_in, 1 = _gpio_reg_out
    // Write
    logic _we;
    assign _we = i_we & i_addr_access;
    always_ff @(posedge i_clk, negedge i_rst) begin : write
        if (~i_rst) begin
            // Yosys does not support 
            // _gpio_reg_out <= '{default:8'b0};
            for (int i = 0; i < SIZEBYTE; i++) _gpio_reg_out[i] <= 8'h0;
        end
        else begin
            if (_we & _reg_select) begin  // 1:out, 0:in
                case(i_mask_type)
                    2'b00:
                        _gpio_reg_out[_addr]   <= i_wd[7:0];
                    2'b01: begin
                        _gpio_reg_out[_addr]   <= i_wd[15:8];
                        _gpio_reg_out[_addr+1] <= i_wd[7:0];
                    end
                    2'b10: begin
                        _gpio_reg_out[_addr]   <= i_wd[31:24];
                        _gpio_reg_out[_addr+1] <= i_wd[23:16];
                        _gpio_reg_out[_addr+2] <= i_wd[15:8];
                        _gpio_reg_out[_addr+3] <= i_wd[7:0];
                    end
                    default: begin
                        /* Do nothing */
                    end 
                endcase
            end
        end
    end
    // Read
    logic _re;
    assign _re = ~i_we & i_addr_access;
    logic [7:0] _gpio_reg_select [SIZEBYTE - 1:0];
    // FU Yosys
    // assign _gpio_reg_select = _reg_select ? _gpio_reg_out : _gpio_reg_in; // 1:out, 0:in
    always_comb begin
        for (int i = 0; i < SIZEBYTE; i++)
            _gpio_reg_select[i] = _reg_select ? _gpio_reg_out[i] : _gpio_reg_in[i];
    end


    always_ff @(posedge i_clk) begin : read
        if (_re) begin
            case(i_mask_type)
                2'b00:
                    o_rd <= {24'b0, _gpio_reg_select[_addr]};
                2'b01:
                    o_rd <= {16'b0, _gpio_reg_select[_addr], _gpio_reg_select[_addr+1]};
                2'b10:
                    o_rd <= {_gpio_reg_select[_addr], _gpio_reg_select[_addr+1], _gpio_reg_select[_addr+2], _gpio_reg_select[_addr+3]};
                default: begin
                    o_rd <= 32'bx; // invalid data
                end
            endcase
        end
        else
            o_rd <= 32'b0; // return 0 to databus
    end

    // ACK
    always_ff @(posedge i_clk) begin : ack
        o_ack <= i_addr_access;
    end

    // ERR
    assign o_err = 1'b0;

endmodule
