// Buffer a complete AXI burst before issuing it. All writes for a descriptor
// have received B responses when done pulses, including on STREAMOFF or error.
module ironcapture_writer #(parameter integer AXI_DATA_WIDTH = 64) (
    input logic clk, reset_n, enable, pending,
    input logic [31:0] base,
    input logic [15:0] width, height,
    output logic taken, busy, done, failed,
    input logic [31:0] pixel_pair,
    input logic valid, sof, eol,
    output logic ready,
    output logic [31:0] awaddr,
    output logic [7:0] awlen,
    output logic awvalid, input logic awready,
    output logic [AXI_DATA_WIDTH-1:0] wdata,
    output logic wvalid, wlast, input logic wready,
    input logic bvalid, input logic [1:0] bresp, output logic bready
);
    localparam integer WORDS = AXI_DATA_WIDTH / 32;
    localparam integer BYTES = AXI_DATA_WIDTH / 8;
    typedef enum logic [2:0] {HUNT, COLLECT, TRANSFER, RESPONSE} state_t;
    state_t state;
    logic [AXI_DATA_WIDTH-1:0] beats [0:15];
    logic [AXI_DATA_WIDTH-1:0] partial, packed_word;
    logic [1:0] lane;
    logic [3:0] fill, last_beat, send_index;
    logic [31:0] next_address;
    logic [15:0] x, y;
    logic terminal, cancel, address_sent, data_sent;
    wire end_line = x + 16'd2 == width;
    wire end_frame = end_line && y + 16'd1 == height;
    initial if (!(AXI_DATA_WIDTH == 32 || AXI_DATA_WIDTH == 64 || AXI_DATA_WIDTH == 128))
        $fatal(1, "Unsupported AXI write width");

    // Hold the SOF word at the stream boundary while accepting its descriptor.
    assign taken = state == HUNT && enable && pending && valid && sof;
    assign ready = (state == HUNT && !taken) || state == COLLECT;
    assign busy = state != HUNT;
    assign awlen = {4'b0,last_beat};
    assign awvalid = state == TRANSFER && !address_sent;
    assign wvalid = state == TRANSFER && !data_sent;
    assign wdata = beats[send_index];
    assign wlast = send_index == last_beat;
    assign bready = state == RESPONSE;
    always_comb begin
        packed_word = partial;
        packed_word[32*lane +: 32] = pixel_pair;
    end

    always_ff @(posedge clk) begin
        done <= 0;
        failed <= 0;
        if (!reset_n) begin
            state <= HUNT;
            awaddr <= 0;
            cancel <= 0;
        end else begin
            if (!enable && busy) cancel <= 1;
            case (state)
                HUNT: if (taken) begin
                    x <= 0;
                    y <= 0;
                    lane <= 0;
                    fill <= 0;
                    cancel <= 0;
                    next_address <= base;
                    awaddr <= base;
                    state <= COLLECT;
                end
                COLLECT: if (!enable || cancel ||
                    (valid && ((sof != (x == 0 && y == 0)) || eol != end_line))) begin
                    state <= HUNT;
                    done <= 1;
                    failed <= 1;
                end else if (valid) begin
                    x <= end_line ? 16'd0 : x + 16'd2;
                    if (end_line) y <= y + 1'b1;
                    partial <= packed_word;
                    if (lane == WORDS-1) begin
                        lane <= 0;
                        beats[fill] <= packed_word;
                        next_address <= next_address + BYTES;
                        // All supported lines contain an integral number of beats.
                        if (fill == 15 || end_line || next_address[11:0] == 4096-BYTES) begin
                            last_beat <= fill;
                            send_index <= 0;
                            address_sent <= 0;
                            data_sent <= 0;
                            terminal <= end_frame;
                            state <= TRANSFER;
                        end else fill <= fill + 1'b1;
                    end else lane <= lane + 1'b1;
                end
                TRANSFER: begin
                    if (awvalid && awready) address_sent <= 1;
                    if (wvalid && wready) begin
                        if (wlast) data_sent <= 1;
                        else send_index <= send_index + 1'b1;
                    end
                    if ((address_sent || awready) && (data_sent || (wlast && wready))) state <= RESPONSE;
                end
                RESPONSE: if (bvalid) begin
                    if (terminal || cancel || !enable || bresp != 0) begin
                        state <= HUNT;
                        done <= 1;
                        failed <= cancel || !enable || bresp != 0;
                    end else begin
                        awaddr <= next_address;
                        fill <= 0;
                        state <= COLLECT;
                    end
                end
            endcase
        end
    end
endmodule
