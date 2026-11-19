`timescale 1ns/1ps

module tb_ironcapture_pattern #(parameter integer MODE_1080 = 0);
    localparam integer WIDTH = MODE_1080 ? 1920 : 1280;
    localparam integer HEIGHT = MODE_1080 ? 1080 : 720;
    localparam integer BEATS = WIDTH * HEIGHT / 4;
    localparam integer CAMERA_CLOCK_HZ = MODE_1080 ? 63000000 : 45000000;
    localparam logic [31:0] BASE = 32'h1001_fff8;
    reg clk = 0, ref_clk = 0, reset_n = 0;
    always #5 clk = !clk;
    always #2.5 ref_clk = !ref_clk;

    reg [12:0] s_awaddr = 0, s_araddr = 0;
    reg [31:0] s_wdata = 0;
    reg s_awvalid = 0, s_wvalid = 0, s_arvalid = 0;
    reg s_bready = 0, s_rready = 0;
    wire s_awready, s_wready, s_bvalid, s_arready, s_rvalid, irq;
    wire [1:0] s_bresp, s_rresp;
    wire [31:0] s_rdata;

    wire [31:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst;
    wire [63:0] wdata;
    wire [7:0] wstrb;
    wire awvalid, awready, wvalid, wready, wlast, bready;
    reg bvalid = 0;

    ironcapture_top #(.AXI_DATA_WIDTH(64), .CAMERA_RX(0), .CLOCK_HZ(CAMERA_CLOCK_HZ)) dut (
        .axi_clk(clk), .reset_n(reset_n), .ref_clk(ref_clk), .irq(irq),
        .dphy_clk_p(1'b0), .dphy_clk_n(1'b0), .dphy_clk_lp_p(1'b0), .dphy_clk_lp_n(1'b0),
        .dphy_dat_p(2'b0), .dphy_dat_n(2'b0), .dphy_dat_lp_p(2'b0), .dphy_dat_lp_n(2'b0),
        .s_axi_awaddr(s_awaddr), .s_axi_awprot(3'b0), .s_axi_awvalid(s_awvalid), .s_axi_awready(s_awready),
        .s_axi_wdata(s_wdata), .s_axi_wstrb(4'hf), .s_axi_wvalid(s_wvalid), .s_axi_wready(s_wready),
        .s_axi_bresp(s_bresp), .s_axi_bvalid(s_bvalid), .s_axi_bready(s_bready),
        .s_axi_araddr(s_araddr), .s_axi_arprot(3'b0), .s_axi_arvalid(s_arvalid), .s_axi_arready(s_arready),
        .s_axi_rdata(s_rdata), .s_axi_rresp(s_rresp), .s_axi_rvalid(s_rvalid), .s_axi_rready(s_rready),
        .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize), .m_axi_awburst(awburst),
        .m_axi_awcache(), .m_axi_awprot(), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast), .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bvalid(bvalid), .m_axi_bresp(2'b00), .m_axi_bready(bready)
    );

    reg [63:0] ddr [0:BEATS-1];
    integer cycles = 0, written = 0, retired = 0, bursts = 0;
    integer declared = 0, received = 0;
    bit have_address = 0, have_data = 0, capturing = 0;
    assign awready = cycles % 7 == 4;
    assign wready = cycles % 5 != 1;

    always @(posedge clk) begin
        if (reset_n) begin
            cycles <= cycles + 1;
            if (awvalid && awready) begin
                if (have_address || awaddr != BASE + retired*8 || awsize != 3 || awburst != 1 ||
                    awlen >= 16 || int'(awaddr[11:0]) + (int'(awlen)+1)*8 > 4096)
                    $fatal(1, "Unexpected DDR AW addr=%h len=%d retired=%d", awaddr, awlen, retired);
                declared <= int'(awlen) + 1;
                have_address <= 1;
            end
            if (wvalid && wready) begin
                if (have_data || wstrb != 8'hff || written >= BEATS)
                    $fatal(1, "Unexpected DDR W");
                ddr[written] <= wdata;
                written <= written + 1;
                received <= received + 1;
                have_data <= wlast;
            end
            if (have_address && have_data) begin
                if (declared != received) $fatal(1, "DDR AWLEN disagrees with WLAST");
                bvalid <= 1;
            end
            if (bvalid && bready) begin
                bvalid <= 0;
                retired <= retired + received;
                bursts <= bursts + 1;
                received <= 0;
                have_address <= 0;
                have_data <= 0;
            end
            if (irq && capturing && retired != BEATS)
                $fatal(1, "Completion before complete frame: %0d/%0d beats", retired, BEATS);
        end
    end

    task automatic axil_write(input [12:0] address, input [31:0] value);
        @(negedge clk);
        // Exercise the public port's W-before-AW support and response holding.
        s_wdata = value;
        s_wvalid = 1;
        do @(posedge clk); while (!s_wready);
        @(negedge clk);
        s_wvalid = 0;
        s_awaddr = address;
        s_awvalid = 1;
        do @(posedge clk); while (!s_awready);
        @(negedge clk);
        s_awvalid = 0;
        wait (s_bvalid);
        repeat (2) @(negedge clk);
        if (!s_bvalid || s_bresp != 0) $fatal(1, "AXI-Lite write %h did not complete", address);
        s_bready = 1;
        @(negedge clk);
        s_bready = 0;
    endtask

    task automatic axil_read(input [12:0] address, output [31:0] value);
        @(negedge clk);
        s_araddr = address;
        s_arvalid = 1;
        do @(posedge clk); while (!s_arready);
        @(negedge clk);
        s_arvalid = 0;
        wait (s_rvalid);
        repeat (2) @(negedge clk);
        if (!s_rvalid || s_rresp != 0) $fatal(1, "AXI-Lite read %h did not complete", address);
        value = s_rdata;
        s_rready = 1;
        @(negedge clk);
        s_rready = 0;
    endtask

    // 75% static bars from the receiver's public YUYV BT.709 contract.
    function automatic [31:0] bar(input int index);
        case (index)
            0: return 32'h80b4_80b4;
            1: return 32'h88a8_2ca8;
            2: return 32'h2c91_9391;
            3: return 32'h3485_3f85;
            4: return 32'hcc3f_c13f;
            5: return 32'hd433_6d33;
            6: return 32'h781c_d41c;
            default: return 32'h8010_8010;
        endcase
    endfunction

    reg [31:0] value, expected;
    initial begin
        repeat (8) @(negedge clk);
        reset_n = 1;
        axil_read(13'h0000, value);
        if (value !== 32'h4943_4150) $fatal(1, "IronCapture ID %h", value);
        axil_read(13'h0008, value);
        if (value !== 32'd8) $fatal(1, "IronCapture bus width %h", value);
        axil_read(13'h1000, value);
        if (value !== 32'h4353_4932) $fatal(1, "Forwarded CSI ID %h", value);
        axil_write(13'h1020, 32'h7c);
        axil_write(13'h1030, 32'h400);
        axil_write(13'h1010, MODE_1080);
        axil_write(13'h1014, 2);
        axil_read(13'h1014, value);
        if (value !== 32'd2) $fatal(1, "Forwarded CSI source did not change: %h", value);

        axil_write(13'h0020, MODE_1080);
        axil_write(13'h0014, BASE+1);
        axil_write(13'h000c, 1);
        axil_write(13'h0018, 1);
        axil_read(13'h0010, value);
        if (!irq || value !== 32'd12 || written != 0)
            $fatal(1, "Unaligned DMA destination was not rejected");
        axil_write(13'h001c, 1);
        axil_write(13'h000c, 0);
        axil_write(13'h0014, BASE);
        capturing = 1;
        axil_write(13'h000c, 1);
        axil_write(13'h0018, 1);
        wait (irq);
        axil_read(13'h0010, value);
        if (value !== 32'd4 || written != BEATS || retired != BEATS || bursts == 0)
            $fatal(1, "Bad completed capture status=%h written=%d retired=%d", value,written,retired);
        for (integer i = 0; i < BEATS; ++i) begin
            expected = bar((i % (WIDTH/4)) / (WIDTH/32));
            if (ddr[i] !== {expected,expected})
                $fatal(1, "DDR beat %d: %h expected %h", i, ddr[i], {expected,expected});
        end
        axil_read(13'h0024, value);
        if (value !== 1) $fatal(1, "Capture completion count %h", value);
        axil_write(13'h001c, 1);
        axil_read(13'h0010, value);
        if (irq || value !== 0) $fatal(1, "IRQ ACK did not clear completion");
        axil_write(13'h000c, 0);
        $display("PASS IronCapture AXI-Lite -> RTLNet static bars -> DDR %0d YUYV bytes in %0d bursts", BEATS*8, bursts);
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1, "Top-level pattern capture timed out (%0d DDR beats)", retired);
    end
endmodule

module tb_ironcapture_pattern1080;
    tb_ironcapture_pattern #(.MODE_1080(1)) capture();
endmodule
