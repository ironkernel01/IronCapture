`timescale 1ns/1ps

module writer_test #(parameter integer AXI_WIDTH = 64) (output reg finished = 0);
    localparam integer BEAT_BYTES = AXI_WIDTH/8;
    localparam integer WORDS = AXI_WIDTH/32;
    localparam integer FRAME_WIDTH = 96;
    localparam integer FRAME_HEIGHT = 3;
    localparam logic [31:0] BASE = 32'h00001ff0;
    reg clk = 0;
    always #5 clk = !clk;

    reg reset_n = 0, enable = 0, pending = 0;
    reg [31:0] pixel_pair = 0;
    reg valid = 0, sof = 0, eol = 0;
    wire taken, busy, done, failed, ready;
    wire [31:0] awaddr;
    wire [7:0] awlen;
    wire awvalid, wvalid, wlast, bready;
    wire [AXI_WIDTH-1:0] wdata;
    wire awready, wready;
    reg bvalid = 0;
    reg [1:0] bresp = 0;

    ironcapture_writer #(.AXI_DATA_WIDTH(AXI_WIDTH)) dut (
        .clk(clk), .reset_n(reset_n), .enable(enable), .pending(pending),
        .base(BASE), .width(16'(FRAME_WIDTH)), .height(16'(FRAME_HEIGHT)),
        .taken(taken), .busy(busy), .done(done), .failed(failed),
        .pixel_pair(pixel_pair), .valid(valid), .sof(sof), .eol(eol), .ready(ready),
        .awaddr(awaddr), .awlen(awlen), .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wvalid(wvalid), .wlast(wlast), .wready(wready),
        .bvalid(bvalid), .bresp(bresp), .bready(bready)
    );

    integer cycle = 0, policy = 0, words = 0, beats = 0, bursts = 0, responses = 0;
    integer expected_beats = 0, beats_in_burst = 0, delay_left = 0;
    bit hold_b = 0, inject_error = 0, got_aw = 0, got_wlast = 0;
    bit saw_w_first = 0, saw_aw_first = 0, saw_4k_split = 0;
    bit past_aw_stall = 0, past_w_stall = 0;
    reg [31:0] past_awaddr;
    reg [7:0] past_awlen;
    reg [AXI_WIDTH-1:0] past_wdata;
    reg past_wlast;

    // Policy 1 withholds AW until the full W burst arrived. Policy 2
    // withholds W until AW arrived. Both add recurring intra-channel stalls.
    assign awready = reset_n && cycle % 5 == 2 && (policy != 1 || got_wlast);
    assign wready = reset_n && cycle % 4 != 0 && (policy != 2 || got_aw);

    function automatic [31:0] word_at(input integer position);
        return 32'h8ae10624 ^ (32'h0103f71d * position);
    endfunction

    always @(posedge clk) begin
        cycle <= cycle + 1;
        if (!reset_n) begin
            words <= 0;
            beats <= 0;
            bursts <= 0;
            responses <= 0;
            beats_in_burst <= 0;
            got_aw <= 0;
            got_wlast <= 0;
            bvalid <= 0;
            saw_w_first <= 0;
            saw_aw_first <= 0;
            saw_4k_split <= 0;
            past_aw_stall <= 0;
            past_w_stall <= 0;
        end else begin
            if (past_aw_stall && (!awvalid || {awaddr,awlen} !== {past_awaddr,past_awlen}))
                $fatal(1, "AXI%0d: AW changed while stalled", AXI_WIDTH);
            if (past_w_stall && (!wvalid || {wdata,wlast} !== {past_wdata,past_wlast}))
                $fatal(1, "AXI%0d: W changed while stalled", AXI_WIDTH);
            past_aw_stall <= awvalid && !awready;
            past_w_stall <= wvalid && !wready;
            {past_awaddr,past_awlen} <= {awaddr,awlen};
            {past_wdata,past_wlast} <= {wdata,wlast};

            if (awvalid && awready) begin
                if (got_aw || awlen >= 16 || awaddr != BASE + beats * BEAT_BYTES)
                    $fatal(1, "AXI%0d: invalid AW address or length", AXI_WIDTH);
                if (int'(awaddr[11:0]) + (int'(awlen)+1)*BEAT_BYTES > 4096)
                    $fatal(1, "AXI%0d: burst crosses 4KiB", AXI_WIDTH);
                if (int'(awaddr[11:0]) + (int'(awlen)+1)*BEAT_BYTES == 4096)
                    saw_4k_split <= 1;
                expected_beats <= int'(awlen) + 1;
                bursts <= bursts + 1;
                got_aw <= 1;
                if (!beats_in_burst && !(wvalid && wready)) saw_aw_first <= 1;
            end
            if (wvalid && wready) begin
                if (got_wlast)
                    $fatal(1, "AXI%0d: W after WLAST", AXI_WIDTH);
                for (integer lane = 0; lane < WORDS; ++lane)
                    if (wdata[lane*32 +: 32] !== word_at(words + lane))
                        $fatal(1, "AXI%0d: word %0d differs: %h", AXI_WIDTH, words+lane, wdata);
                if (!got_aw && !(awvalid && awready)) saw_w_first <= 1;
                words <= words + WORDS;
                beats_in_burst <= beats_in_burst + 1;
                got_wlast <= wlast;
            end
            if (got_aw && got_wlast) begin
                if (beats_in_burst != expected_beats)
                    $fatal(1, "AXI%0d: AWLEN/WLAST mismatch", AXI_WIDTH);
                if (delay_left == 0 && !bvalid && !hold_b) begin
                    bvalid <= 1;
                    bresp <= inject_error ? 2'b10 : 2'b00;
                end else if (delay_left != 0) begin
                    delay_left <= delay_left - 1;
                end
            end
            if (bvalid && bready) begin
                beats <= beats + beats_in_burst;
                responses <= responses + 1;
                got_aw <= 0;
                got_wlast <= 0;
                beats_in_burst <= 0;
                bvalid <= 0;
                delay_left <= 8;
            end
            if (done && (got_aw || got_wlast || bvalid))
                $fatal(1, "AXI%0d: done before response", AXI_WIDTH);
        end
    end

    task automatic reset_test;
        @(negedge clk);
        reset_n = 0;
        enable = 0;
        pending = 0;
        valid = 0;
        hold_b = 0;
        inject_error = 0;
        repeat (2) @(negedge clk);
        reset_n = 1;
        enable = 1;
        pending = 1;
    endtask

    task automatic send(input integer index, input bit start, input bit line_end);
        @(negedge clk);
        valid = 1;
        pixel_pair = word_at(index);
        sof = start;
        eol = line_end;
        do begin
            @(posedge clk);
            if (taken) begin
                @(negedge clk);
                pending = 0;
                @(posedge clk);
            end
        end while (!ready);
        @(negedge clk);
        valid = 0;
    endtask

    task automatic expect_done(input bit expect_failed);
        wait (done);
        if (busy || failed !== expect_failed)
            $fatal(1, "AXI%0d: unexpected completion busy=%b failed=%b", AXI_WIDTH,busy,failed);
        @(negedge clk);
    endtask

    initial begin
        for (integer kind = 1; kind <= 2; ++kind) begin
            reset_test();
            policy = kind;
            fork
                for (integer p = 0; p < FRAME_WIDTH*FRAME_HEIGHT/2; ++p)
                    send(p, p == 0, p % (FRAME_WIDTH/2) == FRAME_WIDTH/2-1);
                expect_done(0);
            join
            if (words != FRAME_WIDTH*FRAME_HEIGHT/2 || responses != bursts || !saw_4k_split ||
                (kind == 1 && !saw_w_first) || (kind == 2 && !saw_aw_first))
                $fatal(1, "AXI%0d: complete frame or handshake coverage missing", AXI_WIDTH);
        end

        reset_test();
        policy = 0;
        // Non-SOF data cannot consume the descriptor. Disable while hunting.
        for (integer p = 0; p < 3; ++p)
            send(p, 0, 0);
        enable = 0;
        repeat (5) @(negedge clk);
        if (busy || done || bursts || words)
            $fatal(1, "AXI%0d: consumed data without SOF", AXI_WIDTH);

        reset_test();
        // Early EOL and unexpected SOF abort before issuing the first burst.
        send(0, 1, 1);
        expect_done(1);
        if (bursts || words) $fatal(1, "AXI%0d: wrote an early-EOL frame", AXI_WIDTH);
        reset_test();
        send(0, 1, 0);
        send(1, 1, 0);
        expect_done(1);
        if (bursts || words) $fatal(1, "AXI%0d: wrote malformed SOF", AXI_WIDTH);

        reset_test();
        // A source stall in COLLECT must release the descriptor on STOP.
        send(0, 1, 0);
        enable = 0;
        expect_done(1);
        if (bursts || words) $fatal(1, "AXI%0d: wrote a partial burst", AXI_WIDTH);

        for (integer stop = 0; stop <= 1; ++stop) begin
            reset_test();
            hold_b = 1;
            inject_error = (stop == 0);
            for (integer p = 0; p < 4; ++p)
                send(p, p == 0, 0);
            wait (bready);
            @(negedge clk);
            if (stop) enable = 0;
            repeat (24) begin
                @(negedge clk);
                if (done || !busy) $fatal(1, "AXI%0d: retired without B", AXI_WIDTH);
            end
            hold_b = 0;
            expect_done(1);
            if (responses != 1 || bursts != 1 || words != 4)
                $fatal(1, "AXI%0d: abort/error response accounting", AXI_WIDTH);
        end
        $display("PASS IronCapture AXI%0d packing, SOF/EOL, 4 KiB, stalls, BRESP and abort", AXI_WIDTH);
        finished = 1;
    end
endmodule

module tb_ironcapture_writer;
    wire [2:0] finished;
    writer_test #(.AXI_WIDTH(32)) axi32(finished[0]);
    writer_test #(.AXI_WIDTH(64)) axi64(finished[1]);
    writer_test #(.AXI_WIDTH(128)) axi128(finished[2]);
    initial begin
        wait (&finished);
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "IronCapture writer test timed out");
    end
endmodule
