`include "srcs/rtl/include/config.svh"

module Top (
    input logic         C_OSC_25,
    // As reset
    input logic         P6_9,
    // LED
    output logic        L_OB
`ifndef BRAM_AS_RAM
    ,
    // RAM IOs
    output logic        R_CLK,
    output logic        R_RAS,
    output logic        R_CAS,
    output logic        R_WE,
    output logic [1:0]  R_BA,
    output logic [10:0] R_A,
    inout  logic [31:0] R_DQ
`endif
`ifdef GPIO_EN
    // 8 inputs 8 outputs
    ,
    // Inputs
    input logic         P6_3,
    input logic         P6_4,
    input logic         P6_5,
    input logic         P6_6,
    input logic         P6_28,
    input logic         P6_27,
    input logic         P6_26,
    input logic         P6_25,
    // Outputs
    output logic        P6_12,
    output logic        P6_13,
    output logic        P6_14,
    output logic        P6_15,
    output logic        P6_16,
    output logic        P6_17,
    output logic        P6_18,
    output logic        P6_19
`endif
`ifdef HDMI_EN
    ,
    output logic        TMDS_CLK_P,
    output logic        TMDS_CLK_N,
    output logic        TMDS_D0_P,
    output logic        TMDS_D1_N,
    output logic        TMDS_D1_P,
    output logic        TMDS_D1_N,
    output logic        TMDS_D2_P,
    output logic        TMDS_D2_N
`endif
);

    // Note to self:
    // All input signals must be driven otherwise yosys get mindf-ed without throwing any error
    // Also ONLY USE YOSYS COMMIT 7c5dba8b7 AND EARLIER, the libmap pass later in later version f-ed up BRAM infer 

    logic _clk_25;
    logic _rst, _ext_rst, _int_rst;
    assign _clk_25 = C_OSC_25;
    assign _rst = P6_9;

    // ==================================================
    // On board LED
    // about >1hz
    logic _led_sig;
    assign L_OB = _led_sig;

    VarClkDivider #(
        .FACTOR_BITS(24)
    ) led_sig (
        .i_clk(_clk_25),
        .i_rst(_int_rst),
        .o_clk(_led_sig)
    );

    // ==================================================
    // PLLs
    logic _clk_40;
    logic _clk_250;
    logic _pll0_lock;
    PLL0 pll0 (
        .i_clk(_clk_25),
        .o_clk_40(_clk_40),
        .o_clk_250(_clk_250),
        .locked(_pll0_lock)
    );

`ifndef BRAM_AS_RAM
    // Check config.svh
    logic _clk_90;
    logic _clk_90_p180;
    logic _pll1_lock;
    PLL1 pll1 (
        .i_clk(_clk_25),
        .o_clk_90(_clk_90),
        .o_clk_90_p180(_clk_90_p180),
        .locked(_pll1_lock)
    );
`endif

    // ==================================================
    // RST gen TODO
    RstGenerator rst_gen (
        .i_clk(_clk_40),
        .i_rst(_rst),
        .i_rst_wdt(1'b1),     // not available
        .o_ext_rst(_ext_rst), // not used
        .o_int_rst(_int_rst) 
    );

    // ==================================================
    // Periphs IOs

`ifndef BRAM_AS_RAM
    logic        _sdram_clk;
    logic        _sdram_ctrl_clk;
    logic        _sdram_ras;
    logic        _sdram_cas;
    logic        _sdram_we;
    logic [1:0]  _sdram_ba;
    logic [31:0] _sdram_addr;
    logic [31:0] _sdram_data;

    assign _sdram_clk = _clk_90_p180;
    assign _sdram_ctrl_clk = _clk_90;

    assign R_CLK = _sdram_clk;
    assign R_RAS = _sdram_ras;
    assign R_CAS = _sdram_cas;
    assign R_WE  = _sdram_we;
    assign R_BA  = _sdram_ba;
    assign R_A   = _sdram_addr;
    assign R_DQ  = _sdram_data;

`endif

`ifdef GPIO_EN
    logic [7:0] btn_in, btn_out;
    logic [7:0] led_out;
    assign btn_in = {~P6_3, ~P6_4, ~P6_5, ~P6_6, P6_28, P6_27, P6_26, P6_25};
    assign {P6_12, P6_19, P6_13, P6_18, P6_14, P6_17, P6_15, P6_16} = led_out;
    genvar i;
    generate
        for (i = 0; i < 8; i++) begin
            Debouncer btn (
                .i_clk(_clk_40),
                .i_rst(_int_rst),
                .i_signal(btn_in[i]),
                .o_state(btn_out[i])
            );
        end
    endgenerate

    logic [31:0] i_gpio_32;
    logic [31:0] o_gpio_32;
    assign i_gpio_32 = {btn_out, 24'h0};
    assign led_out = o_gpio_32[31:24];
`endif // GPIO_EN

`ifdef HDMI_EN
    logic [3:0] _hdmi_dp, _hdmi_dn;
    assign {TMDS_CLK_P, TMDS_D2_P, TMDS_D1_P, TMDS_D0_P} = _hdmi_dp;
    assign {TMDS_CLK_N, TMDS_D2_N, TMDS_D1_N, TMDS_D0_N} = _hdmi_dn;
`endif // HDMI_EN

    // ==================================================
    // CPU
    CPU cpu (
        .i_clk           (_clk_40),
        .i_rst           (_int_rst)
`ifndef BRAM_AS_RAM
        ,
        .i_ram_clk       (_sdram_ctrl_clk),
        .o_ram_ras       (_sdram_ras),
        .o_ram_cas       (_sdram_cas),
        .o_ram_we        (_sdram_we),
        .o_ram_ba        (_sdram_ba),
        .o_ram_addr      (_sdram_addr),
    `ifdef VERILATOR
        // Don't think I'll emu top module
        // .i_ram_dq(),
        // .o_ram_dq()
    `else
        .io_ram_dq       (_sdram_data)
    `endif
`endif
`ifdef GPIO_EN
        ,
        .i_gpio          (i_gpio_32),
        .o_gpio          (o_gpio_32)
`endif
`ifdef HDMI_EN
        ,
        .i_hdmi_pixel_clk(_clk_25),
        .i_hdmi_tmds_clk (_clk_250),
        .o_hdmi_gpdi_dp  (_hdmi_dp), 
        .o_hdmi_gpdi_dn  (_hdmi_dn)
`endif
    );

endmodule
