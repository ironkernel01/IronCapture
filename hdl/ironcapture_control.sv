// One config port. Offsets 0x1000..1fff forward to the complete CSI receiver.
module ironcapture_control #(parameter integer AXI_DATA_WIDTH=64) (
    input logic clk, reset_n,
    input logic [12:0] s_axi_awaddr, s_axi_araddr,
    input logic s_axi_awvalid, s_axi_wvalid, s_axi_bready, s_axi_arvalid, s_axi_rready,
    input logic [31:0] s_axi_wdata, input logic [3:0] s_axi_wstrb,
    output logic s_axi_awready, s_axi_wready, s_axi_bvalid, s_axi_arready, s_axi_rvalid,
    output logic [31:0] s_axi_rdata, output logic [1:0] s_axi_bresp, s_axi_rresp,
    output logic [11:0] rx_awaddr, rx_araddr,
    output logic rx_awvalid, rx_wvalid, rx_bready, rx_arvalid, rx_rready,
    output logic [31:0] rx_wdata, output logic [3:0] rx_wstrb,
    input logic rx_awready, rx_wready, rx_bvalid, rx_arready, rx_rvalid,
    input logic [31:0] rx_rdata, input logic [1:0] rx_bresp, rx_rresp,
    output logic enable, pending, irq,
    output logic [31:0] base, output logic [15:0] width, height,
    input logic taken, busy, done, failed
);
    logic [12:0] write_addr;
    logic have_addr, have_data, write_remote, read_remote;
    logic finished, error;
    logic [31:0] count;
    wire owned = pending || busy || finished || done;
    assign irq = finished;
    assign rx_awaddr = write_addr[11:0];
    assign s_axi_awready = !(have_addr || write_remote || s_axi_bvalid);
    assign s_axi_wready = !(have_data || write_remote || s_axi_bvalid);
    assign s_axi_arready = !(read_remote || s_axi_rvalid);
    assign rx_bready = write_remote;
    assign rx_rready = read_remote;

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            have_addr <= 0; have_data <= 0; read_remote <= 0; write_remote <= 0;
            s_axi_bvalid <= 0; s_axi_rvalid <= 0;
            rx_awvalid <= 0; rx_wvalid <= 0; rx_arvalid <= 0;
            enable <= 0; pending <= 0; finished <= 0; error <= 0; count <= 0;
            width <= 1280; height <= 720; base <= 0;
        end else begin
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 0;
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 0;
            if (taken) pending <= 0;
            if (s_axi_awready && s_axi_awvalid) begin
                have_addr <= 1; write_addr <= s_axi_awaddr;
            end
            if (s_axi_wready && s_axi_wvalid) begin
                have_data <= 1; rx_wdata <= s_axi_wdata; rx_wstrb <= s_axi_wstrb;
            end
            if (have_data && have_addr) begin
                have_addr <= 0; have_data <= 0;
                if (write_addr[12]) begin
                    write_remote <= 1;
                    rx_awvalid <= 1; rx_wvalid <= 1;
                end else begin
                    s_axi_bvalid <= 1; s_axi_bresp <= 0;
                    if (rx_wstrb == 4'hf) case (write_addr[11:0])
                        12'h00c: begin
                            enable <= rx_wdata[0];
                            if (!rx_wdata[0]) pending <= 0;
                        end
                        12'h014: if (!owned) base <= rx_wdata;
                        12'h018: if (!owned && enable && rx_wdata[0]) begin
                            if ((base & (AXI_DATA_WIDTH/8-1)) == 0 &&
                                {1'b0,base} + (width == 1280 ? 33'd1843200 : 33'd4147200) <= 33'h100000000)
                                pending <= 1;
                            else begin finished <= 1; error <= 1; end
                        end
                        12'h01c: if (rx_wdata[0]) begin finished <= 0; error <= 0; end
                        12'h020: if (!enable && !owned) begin
                            width <= rx_wdata[0] ? 1920 : 1280;
                            height <= rx_wdata[0] ? 1080 : 720;
                        end
                        default: ;
                    endcase
                end
            end
            if (rx_awvalid && rx_awready) rx_awvalid <= 0;
            if (rx_wvalid && rx_wready) rx_wvalid <= 0;
            if (write_remote && rx_bvalid) begin
                s_axi_bvalid <= 1; s_axi_bresp <= rx_bresp; write_remote <= 0;
            end
            if (s_axi_arready && s_axi_arvalid) begin
                if (s_axi_araddr[12]) begin
                    rx_araddr <= s_axi_araddr[11:0];
                    rx_arvalid <= 1; read_remote <= 1;
                end else begin
                    s_axi_rvalid <= 1; s_axi_rresp <= 0;
                    case (s_axi_araddr[11:0])
                        12'h000: s_axi_rdata <= 32'h49434150;
                        12'h004: s_axi_rdata <= 1;
                        12'h008: s_axi_rdata <= AXI_DATA_WIDTH/8;
                        12'h00c: s_axi_rdata <= {31'b0,enable};
                        12'h010: s_axi_rdata <= {28'b0,error,finished,pending,busy || done};
                        12'h014: s_axi_rdata <= base;
                        12'h020: s_axi_rdata <= {31'b0,width == 1920};
                        12'h024: s_axi_rdata <= count;
                        default: s_axi_rdata <= 0;
                    endcase
                end
            end
            if (rx_arvalid && rx_arready) rx_arvalid <= 0;
            if (read_remote && rx_rvalid) begin
                s_axi_rvalid <= 1; s_axi_rdata <= rx_rdata; s_axi_rresp <= rx_rresp;
                read_remote <= 0;
            end
            if (done) begin finished <= 1; error <= failed; count <= count + 1'b1; end
        end
    end
endmodule
