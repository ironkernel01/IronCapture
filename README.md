# IronCapture

[Product specification (PDF)](documentation/ironcapture_specification.pdf) · [Markdown](documentation/ironcapture_specification.md)

IronCapture captures a two-lane MIPI CSI-2 camera into DDR. One Vivado module
reference, `ironcapture_top`, contains the RTLNet receiver, Bayer processing,
YUV422 conversion, AXI4-Lite configuration and an AXI4 write master. Each
completed buffer is a packed YUYV frame in byte order Y0, Cb, Y1, Cr.
The sensor modes are 1280 × 720 and 1920 × 1080 at 30 frames per second.
The Linux capture device also provides an internal color-bar input.

## Source and integration

IronCapture owns the CSI-2 RTL, freestanding register driver, models, benches
and documentation in `ip/rtlnet_csi2_rx/`. Both hardware tops use that receiver.

| Top | Interface and use |
| --- | --- |
| `rtlnet_csi2_rx` | AXI4-Lite control and a backpressured AXI4-Stream YUYV output, with frame and line markers. The RTLNet bare-metal demo connects this top to its capture DMA and frame manager. Its register driver is under `ip/rtlnet_csi2_rx/driver/`. |
| `ironcapture_top` | AXI4-Lite control and an AXI4 memory write master. This top submits frames directly to DDR, exposes the receiver at offset `0x1000`, and supports the freestanding and Linux drivers below. |

Source `scripts/sources.tcl` in Vivado. Call `ironcapture_add_stream_sources <RTLNet-root>`
for the streaming top or `ironcapture_add_sources <RTLNet-root>` for the memory
writer. The external input is the RTLNet common primitives under `cores/rtlnet_common/`.
`scripts/resolve-receiver.ps1` locates these primitives and verifies their
Git tree against `rtlnet-common.lock.json`. The receiver keeps its original
license in `ip/rtlnet_csi2_rx/LICENSE.md`.

Set `AXI_DATA_WIDTH` to 32, 64 or 128. Connect S_AXI and M_AXI to
`axi_clk`, set `CLOCK_HZ` to that clock's frequency, and supply a 200 MHz
`ref_clk` to the 7-series D-PHY. `reset_n` is active low. Connect the HS and
LP pins with the board's electrical constraints. The Zybo Z7-20 uses a
64-bit Zynq high-performance port, board termination, and a level-high IRQ.
Software submits a 32-bit DMA address aligned to the AXI beat. The buffer
holds exactly width × height × 2 bytes with tightly packed rows. Bursts are
at most 16 beats and stop at each line end and 4 KiB boundary.

## Driver

`driver/ironcapture.c` and `driver/ironcapture.h` contain the freestanding
register API. Linux and bare-metal applications compile this same source.
Supply ordered MMIO read/write callbacks. On bare metal, allocate a DMA-safe
buffer and handle cache ownership according to the platform. Call
`ic_probe`, `ic_configure`, optionally `ic_tune`, then `ic_start` and
`ic_submit`. Poll `ic_status` or handle the interrupt. When `IC_DONE` is
set, inspect `IC_ERROR`, acknowledge with `ic_ack`, and submit the next
buffer. A consumer must finish reading before it resubmits a buffer. A stop
discards an unused descriptor and drains any issued AXI transaction. Poll
until both `IC_BUSY` and `IC_PENDING` clear before reclaiming memory.

The Linux adapter in the same folder provides a V4L2 single-plane streaming
capture device with MMAP buffers. Input 0 selects the sensor and input 1
selects the internal pattern. The device-tree compatible is
`ironkernel,ironcapture-1.0`; its endpoint references the camera sensor on
I²C. The Pcam 5C integration uses the OV5640 driver with RAW10 support.
An application requests `V4L2_PIX_FMT_YUYV` and dequeues frames. IronVideo
can scan out a DRM framebuffer in the matching `DRM_FORMAT_YUYV` format.

## Register map

Registers are 32-bit little-endian. Use full-word writes.

| Offset | Register | Meaning |
|---|---|---|
| 0x000 | ID | 0x49434150 |
| 0x004 | Version | Register interface version 1 |
| 0x008 | Beat size | Implemented AXI master width in bytes |
| 0x00c | Control | Bit 0 enables buffer submission and capture |
| 0x010 | Status | Bit 0 busy, bit 1 pending, bit 2 done, bit 3 frame or AXI error |
| 0x014 | Base | Next contiguous destination address |
| 0x018 | Submit | Write 1 to arm a buffer at the next frame start |
| 0x01c | Acknowledge | Write 1 to clear completion, error and IRQ |
| 0x020 | Mode | 0 selects 720p, 1 selects 1080p. Program while idle and disabled |
| 0x024 | Completions | Number of retired transfers, including errors |
| 0x1000–0x1fff | Receiver | Original RTLNet CSI-2 register map including packet and overflow counters |

The writer holds a single descriptor in hardware. Linux maintains the buffer
queue. Without an armed buffer the receiver stream is consumed and discarded.
Success requires the expected frame geometry and successful write responses.
The receiver's packet and Bayer-size counters provide additional sensor-side
diagnostics, including CRC errors in packets whose pixels were forwarded.
