/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef IRONCAPTURE_H
#define IRONCAPTURE_H

/* Callbacks access ordered little-endian 32-bit memory-mapped registers. */
struct ic_device {
	void *context;
	unsigned int (*read)(void *context, unsigned int offset);
	void (*write)(void *context, unsigned int offset, unsigned int value);
};

enum ic_register {
	IC_ID = 0, IC_VERSION = 4, IC_BEAT_BYTES = 8, IC_CONTROL = 12,
	IC_STATUS = 16, IC_BASE = 20, IC_SUBMIT = 24, IC_ACK = 28,
	IC_MODE = 32, IC_FRAMES = 36, IC_CSI = 0x1000
};
enum ic_status_flag {
	IC_BUSY = 1, IC_PENDING = 2, IC_DONE = 4, IC_ERROR = 8
};
int ic_probe(struct ic_device *dev);
int ic_configure(struct ic_device *dev, unsigned int width, unsigned int height,
		 unsigned int pattern);
int ic_tune(struct ic_device *dev, unsigned int tap0, unsigned int tap1,
	    unsigned int phase, unsigned int bit_reverse);
void ic_start(struct ic_device *dev);
int ic_submit(struct ic_device *dev, unsigned int address, unsigned int capacity);
unsigned int ic_status(struct ic_device *dev);
void ic_ack(struct ic_device *dev);
void ic_stop(struct ic_device *dev);
#endif
