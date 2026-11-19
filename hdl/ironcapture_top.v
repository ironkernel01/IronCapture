`timescale 1ns/1ps
// IronCapture public Vivado module reference. Both AXI buses share axi_clk.
module ironcapture_top #(
    parameter integer AXI_DATA_WIDTH = 64,
    parameter integer CLOCK_HZ = 100000000,
    parameter integer CAMERA_RX = 1,
    parameter DPHY_TARGET = "AMD",
    parameter integer HS_DIFF_TERM = 0
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 axi_clk CLK", X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI:M_AXI, ASSOCIATED_RESET reset_n" *)
    input wire axi_clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 reset_n RST", X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input wire reset_n,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ref_clk CLK", X_INTERFACE_PARAMETER = "FREQ_HZ 200000000" *)
    input wire ref_clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 irq INTERRUPT", X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *)
    output wire irq,
    input wire dphy_clk_p,
    input wire dphy_clk_n,
    input wire dphy_clk_lp_p,
    input wire dphy_clk_lp_n,
    input wire [1:0] dphy_dat_p,
    input wire [1:0] dphy_dat_n,
    input wire [1:0] dphy_dat_lp_p,
    input wire [1:0] dphy_dat_lp_n,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR", X_INTERFACE_PARAMETER = "PROTOCOL AXI4LITE, ADDR_WIDTH 13, DATA_WIDTH 32" *)
    input  wire [12:0] s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input  wire [2:0] s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [3:0] s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output wire [1:0] s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output wire s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [12:0] s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input  wire [2:0] s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output wire [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output wire [1:0] s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output wire s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire s_axi_rready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWADDR", X_INTERFACE_PARAMETER = "PROTOCOL AXI4, READ_WRITE_MODE WRITE_ONLY, ADDR_WIDTH 32, HAS_BURST 1, MAX_BURST_LENGTH 16, SUPPORTS_NARROW_BURST 0, NUM_WRITE_OUTSTANDING 1" *)
    output wire [31:0] m_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLEN" *)
    output wire [7:0] m_axi_awlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWSIZE" *)
    output wire [2:0] m_axi_awsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWBURST" *)
    output wire [1:0] m_axi_awburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWCACHE" *)
    output wire [3:0] m_axi_awcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWPROT" *)
    output wire [2:0] m_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWVALID" *)
    output wire m_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWREADY" *)
    input  wire m_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WDATA" *)
    output wire [AXI_DATA_WIDTH-1:0] m_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WSTRB" *)
    output wire [AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WLAST" *)
    output wire m_axi_wlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WVALID" *)
    output wire m_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WREADY" *)
    input  wire m_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BVALID" *)
    input  wire m_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BRESP" *)
    input  wire [1:0] m_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BREADY" *)
    output wire m_axi_bready
);
    wire pending, taken, busy, done, failed, enable;
    wire [31:0] base, pixel_pair;
    wire [15:0] width, height;
    wire valid, ready, sof, eol;
    wire [11:0] rx_awaddr;
    wire rx_awvalid;
    wire rx_awready;
    wire [31:0] rx_wdata;
    wire [3:0] rx_wstrb;
    wire rx_wvalid;
    wire rx_wready;
    wire [1:0] rx_bresp;
    wire rx_bvalid;
    wire rx_bready;
    wire [11:0] rx_araddr;
    wire rx_arvalid;
    wire rx_arready;
    wire [31:0] rx_rdata;
    wire [1:0] rx_rresp;
    wire rx_rvalid;
    wire rx_rready;
    assign m_axi_awsize = $clog2(AXI_DATA_WIDTH/8);
    assign m_axi_awburst = 2'b01;
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot = 0;
    assign m_axi_wstrb = {AXI_DATA_WIDTH/8{1'b1}};

    ironcapture_control #(.AXI_DATA_WIDTH(AXI_DATA_WIDTH)) control (
        .clk(axi_clk), .reset_n(reset_n),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .rx_awaddr(rx_awaddr),
        .rx_awvalid(rx_awvalid),
        .rx_awready(rx_awready),
        .rx_wdata(rx_wdata),
        .rx_wstrb(rx_wstrb),
        .rx_wvalid(rx_wvalid),
        .rx_wready(rx_wready),
        .rx_bresp(rx_bresp),
        .rx_bvalid(rx_bvalid),
        .rx_bready(rx_bready),
        .rx_araddr(rx_araddr),
        .rx_arvalid(rx_arvalid),
        .rx_arready(rx_arready),
        .rx_rdata(rx_rdata),
        .rx_rresp(rx_rresp),
        .rx_rvalid(rx_rvalid),
        .rx_rready(rx_rready),
        .enable(enable), .pending(pending), .irq(irq), .base(base),
        .width(width), .height(height), .taken(taken), .busy(busy), .done(done), .failed(failed)
    );
    rtlnet_csi2_rx #(
        .AXIL_SYNC(1), .CAMERA_RX(CAMERA_RX), .DPHY_TARGET(DPHY_TARGET),
        .HS_DIFF_TERM(HS_DIFF_TERM), .PERIOD_RESET((CLOCK_HZ+29)/30),
        .LINE_PERIOD_720(CLOCK_HZ/22500), .LINE_PERIOD_1080(CLOCK_HZ/33750),
        .PERIOD_MIN_720(750*(CLOCK_HZ/22500)), .PERIOD_MIN_1080(1125*(CLOCK_HZ/33750))
    ) receiver (
        .clk(axi_clk), .resetn(reset_n), .s_axi_aclk(axi_clk), .s_axi_aresetn(reset_n),
        .ref_clk(ref_clk), .dphy_clk_p(dphy_clk_p),
        .dphy_clk_n(dphy_clk_n),
        .dphy_clk_lp_p(dphy_clk_lp_p),
        .dphy_clk_lp_n(dphy_clk_lp_n),
        .dphy_dat_p(dphy_dat_p),
        .dphy_dat_n(dphy_dat_n),
        .dphy_dat_lp_p(dphy_dat_lp_p),
        .dphy_dat_lp_n(dphy_dat_lp_n),
        .s_cam_tdata(32'b0), .s_cam_tvalid(1'b0), .s_cam_tlast(1'b0),
        .s_cam_tuser(1'b0), .s_cam_tready(), .cam_clk_running(1'b0),
        .m_axis_tdata(pixel_pair), .m_axis_tvalid(valid), .m_axis_tready(ready),
        .m_axis_tuser(sof), .m_axis_tlast(eol), .m_frame_num(), .m_timestamp(),
        .m_width(), .m_height(), .m_src_pattern(),
        .s_axi_awaddr(rx_awaddr),
        .s_axi_awvalid(rx_awvalid),
        .s_axi_awready(rx_awready),
        .s_axi_wdata(rx_wdata),
        .s_axi_wstrb(rx_wstrb),
        .s_axi_wvalid(rx_wvalid),
        .s_axi_wready(rx_wready),
        .s_axi_bresp(rx_bresp),
        .s_axi_bvalid(rx_bvalid),
        .s_axi_bready(rx_bready),
        .s_axi_araddr(rx_araddr),
        .s_axi_arvalid(rx_arvalid),
        .s_axi_arready(rx_arready),
        .s_axi_rdata(rx_rdata),
        .s_axi_rresp(rx_rresp),
        .s_axi_rvalid(rx_rvalid),
        .s_axi_rready(rx_rready)
    );
    ironcapture_writer #(.AXI_DATA_WIDTH(AXI_DATA_WIDTH)) writer (
        .clk(axi_clk), .reset_n(reset_n), .enable(enable), .pending(pending),
        .base(base), .width(width), .height(height), .taken(taken), .busy(busy),
        .done(done), .failed(failed), .pixel_pair(pixel_pair), .valid(valid),
        .ready(ready), .sof(sof), .eol(eol),
        .awaddr(m_axi_awaddr),
        .awlen(m_axi_awlen),
        .awvalid(m_axi_awvalid),
        .awready(m_axi_awready),
        .wdata(m_axi_wdata),
        .wlast(m_axi_wlast),
        .wvalid(m_axi_wvalid),
        .wready(m_axi_wready),
        .bvalid(m_axi_bvalid),
        .bresp(m_axi_bresp),
        .bready(m_axi_bready)
    );
endmodule
