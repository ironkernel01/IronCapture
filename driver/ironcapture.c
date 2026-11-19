/* SPDX-License-Identifier: GPL-2.0-only */
#include "ironcapture.h"

static unsigned int read_reg(struct ic_device *dev, unsigned int reg)
{
	return dev->read(dev->context, reg);
}

static void write_reg(struct ic_device *dev, unsigned int reg, unsigned int value)
{
	dev->write(dev->context, reg, value);
}

int ic_probe(struct ic_device *dev)
{
	unsigned int beat;
	if (!dev || !dev->read || !dev->write || read_reg(dev, IC_ID) != 0x49434150 ||
	    read_reg(dev, IC_VERSION) != 1 || read_reg(dev, IC_CSI) != 0x43534932)
		return -1;
	beat = read_reg(dev, IC_BEAT_BYTES);
	return beat == 4 || beat == 8 || beat == 16 ? 0 : -1;
}

unsigned int ic_status(struct ic_device *dev)
{
	return read_reg(dev, IC_STATUS);
}

int ic_configure(struct ic_device *dev, unsigned int width, unsigned int height,
		 unsigned int pattern)
{
	unsigned int mode = width == 1920 && height == 1080;
	if ((!mode && !(width == 1280 && height == 720)) || pattern > 1 ||
	    read_reg(dev, IC_CONTROL) || ic_status(dev) ||
	    (!pattern && !(read_reg(dev, IC_CSI + 8) & (1U << 5))))
		return -1;
	write_reg(dev, IC_MODE, mode);
	write_reg(dev, IC_CSI + 0x10, mode);
	write_reg(dev, IC_CSI + 0x14, pattern ? 2 : 1);
	return 0;
}

int ic_tune(struct ic_device *dev, unsigned int tap0, unsigned int tap1,
	    unsigned int phase, unsigned int bit_reverse)
{
	unsigned int control = 0x0d | (bit_reverse << 4);
	if (tap0 > 31 || tap1 > 31 || phase > 3 || bit_reverse > 1 ||
	    read_reg(dev, IC_CONTROL) || ic_status(dev))
		return -1;
	write_reg(dev, IC_CSI + 0x40, control | 2);
	write_reg(dev, IC_CSI + 0x48, tap0 | (tap1 << 8));
	write_reg(dev, IC_CSI + 0xa0, phase);
	write_reg(dev, IC_CSI + 0x40, control);
	return 0;
}

void ic_start(struct ic_device *dev)
{
	write_reg(dev, IC_CONTROL, 1);
}

int ic_submit(struct ic_device *dev, unsigned int address, unsigned int capacity)
{
	unsigned int beat = read_reg(dev, IC_BEAT_BYTES);
	unsigned int size = read_reg(dev, IC_MODE) ? 1920U*1080*2 : 1280U*720*2;
	if (!beat || (address & (beat - 1)) || capacity < size ||
	    address > 0xffffffffU - (size - 1) || !read_reg(dev, IC_CONTROL) ||
	    ic_status(dev))
		return -1;
	write_reg(dev, IC_BASE, address);
	write_reg(dev, IC_SUBMIT, 1);
	return 0;
}

void ic_ack(struct ic_device *dev)
{
	write_reg(dev, IC_ACK, 1);
}

void ic_stop(struct ic_device *dev)
{
	write_reg(dev, IC_CONTROL, 0);
	/* Flush a posted write before the caller polls for DMA quiescence. */
	(void)read_reg(dev, IC_CONTROL);
}
