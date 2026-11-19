/* SPDX-License-Identifier: GPL-2.0-only */
#include "../driver/ironcapture.h"
#include <assert.h>

static unsigned int regs[0x2000/4];
static unsigned int rd(void *context, unsigned int offset)
{
	return ((unsigned int *)context)[offset/4];
}
static void wr(void *context, unsigned int offset, unsigned int value)
{
	((unsigned int *)context)[offset/4] = value;
}

int main(void)
{
	struct ic_device dev = { regs, rd, wr };
	unsigned int beat;
	regs[IC_ID/4] = 0x49434150;
	regs[IC_VERSION/4] = 1;
	regs[IC_CSI/4] = 0x43534932;
	for (beat = 4; beat <= 16; beat *= 2) {
		regs[IC_BEAT_BYTES/4] = beat;
		assert(ic_probe(&dev) == 0);
		assert(ic_configure(&dev, 1280, 720, 0) < 0);
		assert(ic_configure(&dev, 1280, 720, 1) == 0);
		regs[(IC_CSI+8)/4] = 32;
		assert(ic_configure(&dev, 1920, 1080, 0) == 0);
		assert(ic_tune(&dev, 11, 10, 3, 0) == 0);
		assert(rd(regs, IC_CSI+0x48) == 0x0a0b);
		ic_start(&dev);
		assert(ic_submit(&dev, 0x10000001, 4147200) < 0);
		assert(ic_submit(&dev, 0xfffffff0, 4147200) < 0);
		assert(ic_submit(&dev, 0x10000000, 4147199) < 0);
		assert(ic_submit(&dev, 0x10000000, 4147200) == 0);
		regs[IC_STATUS/4] = IC_PENDING;
		assert(ic_submit(&dev, 0x12000000, 4147200) < 0);
		assert(rd(regs, IC_BASE) == 0x10000000);
		ic_stop(&dev);
		ic_ack(&dev);
		regs[IC_STATUS/4] = 0;
		regs[(IC_CSI+8)/4] = 0;
	}
	return 0;
}
