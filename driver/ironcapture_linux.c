// SPDX-License-Identifier: GPL-2.0-only
#include <linux/dma-mapping.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/iopoll.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/property.h>
#include <linux/slab.h>
#include <media/v4l2-async.h>
#include <media/v4l2-common.h>
#include <media/v4l2-device.h>
#include <media/v4l2-ioctl.h>
#include <media/v4l2-subdev.h>
#include <media/videobuf2-dma-contig.h>
#include "ironcapture.h"

#define IC_INPUT_SENSOR 0
#define IC_INPUT_PATTERN 1
#define IC_FPS 30

static const struct v4l2_frmsize_discrete ic_sizes[] = {
	{ 1280, 720 },
	{ 1920, 1080 },
};

struct ic_buffer {
	struct vb2_v4l2_buffer vb;
	struct list_head list;
};

struct ic_capture {
	struct device *dev;
	void __iomem *registers;
	int irq;
	struct ic_device hw;
	struct v4l2_device v4l2;
	struct video_device video;
	struct vb2_queue queue;
	struct v4l2_async_notifier notifier;
	struct v4l2_subdev *sensor;
	struct mutex lock;
	spinlock_t dma_lock;
	struct list_head pending;
	struct ic_buffer *active;
	bool running;
	bool sensor_streaming;
	u32 input;
	u32 sequence;
	u64 completed_frames, completed_bytes, dma_errors;
	struct v4l2_pix_format format;
	u32 taps0, taps1, phase;
	bool tune, bit_reverse;
};

static unsigned int ic_read_reg(void *context, unsigned int offset)
{
	struct ic_capture *cap = context;

	return readl(cap->registers + offset);
}

static void ic_write_reg(void *context, unsigned int offset, unsigned int value)
{
	struct ic_capture *cap = context;

	writel(value, cap->registers + offset);
}

/* dma_lock serializes the hardware and buffer transitions with the IRQ. */
static void ic_issue(struct ic_capture *cap)
{
	struct ic_buffer *buf;
	dma_addr_t address;

	while (cap->running && !cap->active && !list_empty(&cap->pending)) {
		buf = list_first_entry(&cap->pending, struct ic_buffer, list);
		list_del(&buf->list);
		address = vb2_dma_contig_plane_dma_addr(&buf->vb.vb2_buf, 0);
		if (!ic_submit(&cap->hw, lower_32_bits(address), cap->format.sizeimage)) {
			cap->active = buf;
			return;
		}
		dev_err_ratelimited(cap->dev, "IronCapture rejected the DMA buffer\n");
		vb2_buffer_done(&buf->vb.vb2_buf, VB2_BUF_STATE_ERROR);
	}
}

static irqreturn_t ic_interrupt(int irq, void *data)
{
	struct ic_capture *cap = data;
	struct ic_buffer *buf;
	u32 status;

	spin_lock(&cap->dma_lock);
	status = ic_status(&cap->hw);
	if (!(status & IC_DONE)) {
		spin_unlock(&cap->dma_lock);
		return IRQ_NONE;
	}
	ic_ack(&cap->hw);
	if (cap->running && cap->active) {
		buf = cap->active;
		cap->active = NULL;
		buf->vb.vb2_buf.timestamp = ktime_get_ns();
		buf->vb.sequence = cap->sequence++;
		buf->vb.field = V4L2_FIELD_NONE;
		if (status & IC_ERROR) {
			cap->dma_errors++;
		} else {
			cap->completed_frames++;
			cap->completed_bytes += cap->format.sizeimage;
		}
		vb2_buffer_done(&buf->vb.vb2_buf, status & IC_ERROR ?
				VB2_BUF_STATE_ERROR : VB2_BUF_STATE_DONE);
		ic_issue(cap);
	}
	spin_unlock(&cap->dma_lock);
	return IRQ_HANDLED;
}

static void ic_return_buffers(struct ic_capture *cap, enum vb2_buffer_state state)
{
	struct ic_buffer *buf, *next;
	unsigned long flags;

	spin_lock_irqsave(&cap->dma_lock, flags);
	if (cap->active) {
		vb2_buffer_done(&cap->active->vb.vb2_buf, state);
		cap->active = NULL;
	}
	list_for_each_entry_safe(buf, next, &cap->pending, list) {
		list_del(&buf->list);
		vb2_buffer_done(&buf->vb.vb2_buf, state);
	}
	spin_unlock_irqrestore(&cap->dma_lock, flags);
}

static int ic_queue_setup(struct vb2_queue *queue, unsigned int *buffers,
			  unsigned int *planes, unsigned int sizes[],
			  struct device *alloc_devs[])
{
	struct ic_capture *cap = vb2_get_drv_priv(queue);

	/* The encoder reads complete 16-line macroblock rows. Keep the visible
	 * V4L2 payload unchanged and reserve the cropped tail in the DMA plane. */
	unsigned int bytes = cap->format.bytesperline * ALIGN(cap->format.height, 16);

	if (*planes)
		return *planes == 1 && sizes[0] >= bytes ? 0 : -EINVAL;
	*planes = 1;
	sizes[0] = bytes;
	return 0;
}

static int ic_buffer_prepare(struct vb2_buffer *vb)
{
	struct ic_capture *cap = vb2_get_drv_priv(vb->vb2_queue);

	if (vb2_plane_size(vb, 0) < cap->format.sizeimage)
		return -EINVAL;
	vb2_set_plane_payload(vb, 0, cap->format.sizeimage);
	return 0;
}

static void ic_buffer_queue(struct vb2_buffer *vb)
{
	struct ic_capture *cap = vb2_get_drv_priv(vb->vb2_queue);
	struct ic_buffer *buf = container_of(to_vb2_v4l2_buffer(vb), struct ic_buffer, vb);
	unsigned long flags;

	spin_lock_irqsave(&cap->dma_lock, flags);
	list_add_tail(&buf->list, &cap->pending);
	ic_issue(cap);
	spin_unlock_irqrestore(&cap->dma_lock, flags);
}

static void ic_drain(struct ic_capture *cap)
{
	unsigned long flags;
	u32 status;
	int ret;

	spin_lock_irqsave(&cap->dma_lock, flags);
	cap->running = false;
	ic_stop(&cap->hw);
	spin_unlock_irqrestore(&cap->dma_lock, flags);
	/* Keep the DMA destination pinned until the final AXI write retires. */
	do {
		ret = read_poll_timeout(ic_status, status, !(status & (IC_BUSY | IC_PENDING)),
					100, 250000, false, &cap->hw);
		if (ret)
			dev_err_ratelimited(cap->dev, "waiting for IronCapture DMA to stop\n");
	} while (ret);
	synchronize_irq(cap->irq);
	spin_lock_irqsave(&cap->dma_lock, flags);
	ic_ack(&cap->hw);
	spin_unlock_irqrestore(&cap->dma_lock, flags);
}

static int ic_start_streaming(struct vb2_queue *queue, unsigned int count)
{
	struct ic_capture *cap = vb2_get_drv_priv(queue);
	struct v4l2_subdev_format format = {
		.which = V4L2_SUBDEV_FORMAT_ACTIVE,
		.pad = 0,
		.format = {
			.width = cap->format.width,
			.height = cap->format.height,
			.code = MEDIA_BUS_FMT_SBGGR10_1X10,
			.field = V4L2_FIELD_NONE,
		},
	};
	struct v4l2_subdev_frame_interval interval = {
		.which = V4L2_SUBDEV_FORMAT_ACTIVE,
		.pad = 0,
		.interval = { .numerator = 1, .denominator = IC_FPS },
	};
	bool pattern = cap->input == IC_INPUT_PATTERN;
	unsigned long flags;
	int ret;

	if (!pattern) {
		if (!cap->sensor) {
			ret = -ENOLINK;
			goto fail;
		}
		ret = v4l2_subdev_call_state_active(cap->sensor, pad, set_fmt, &format);
		if (ret)
			goto fail;
		if (format.format.width != cap->format.width ||
		    format.format.height != cap->format.height ||
		    format.format.code != MEDIA_BUS_FMT_SBGGR10_1X10) {
			ret = -EINVAL;
			goto fail;
		}
		ret = v4l2_subdev_call_state_active(cap->sensor, pad, set_frame_interval, &interval);
		if (ret)
			goto fail;
		if (!interval.interval.numerator ||
		    interval.interval.denominator != (u64)interval.interval.numerator * IC_FPS) {
			ret = -EINVAL;
			goto fail;
		}
	}
	spin_lock_irqsave(&cap->dma_lock, flags);
	ret = ic_configure(&cap->hw, cap->format.width, cap->format.height, pattern);
	if (!ret && cap->tune)
		ret = ic_tune(&cap->hw, cap->taps0, cap->taps1, cap->phase, cap->bit_reverse);
	spin_unlock_irqrestore(&cap->dma_lock, flags);
	if (ret) {
		ret = -EIO;
		goto fail;
	}
	if (!pattern) {
		ret = v4l2_subdev_call(cap->sensor, video, s_stream, 1);
		if (ret)
			goto fail;
		cap->sensor_streaming = true;
	}
	spin_lock_irqsave(&cap->dma_lock, flags);
	ic_ack(&cap->hw);
	ic_start(&cap->hw);
	cap->sequence = 0;
	cap->running = true;
	ic_issue(cap);
	spin_unlock_irqrestore(&cap->dma_lock, flags);
	return 0;
fail:
	ic_return_buffers(cap, VB2_BUF_STATE_QUEUED);
	return ret;
}

static void ic_stop_streaming(struct vb2_queue *queue)
{
	struct ic_capture *cap = vb2_get_drv_priv(queue);

	ic_drain(cap);
	if (cap->sensor_streaming) {
		v4l2_subdev_call(cap->sensor, video, s_stream, 0);
		cap->sensor_streaming = false;
	}
	ic_return_buffers(cap, VB2_BUF_STATE_ERROR);
}

static int ic_buffer_init(struct vb2_buffer *vb)
{
	struct ic_capture *cap = vb2_get_drv_priv(vb->vb2_queue);
	unsigned int end = cap->format.bytesperline * ALIGN(cap->format.height, 16);
	unsigned int visible = cap->format.sizeimage;
	void *data;

	if (end <= visible)
		return 0;
	data = vb2_plane_vaddr(vb, 0);
	if (!data || vb2_plane_size(vb, 0) < end)
		return -EINVAL;
	memset32(data + visible, 0x80108010, (end - visible) / sizeof(u32));
	return 0;
}

static const struct vb2_ops ic_queue_ops = {
	.queue_setup = ic_queue_setup,
	.buf_init = ic_buffer_init,
	.buf_prepare = ic_buffer_prepare,
	.buf_queue = ic_buffer_queue,
	.start_streaming = ic_start_streaming,
	.stop_streaming = ic_stop_streaming,
};

static int ic_querycap(struct file *file, void *priv, struct v4l2_capability *caps)
{
	struct ic_capture *cap = video_drvdata(file);

	strscpy(caps->driver, "ironcapture", sizeof(caps->driver));
	strscpy(caps->card, "IronKernel IronCapture", sizeof(caps->card));
	snprintf(caps->bus_info, sizeof(caps->bus_info), "platform:%s", dev_name(cap->dev));
	return 0;
}

static int ic_enum_fmt(struct file *file, void *priv, struct v4l2_fmtdesc *format)
{
	if (format->index)
		return -EINVAL;
	format->pixelformat = V4L2_PIX_FMT_YUYV;
	return 0;
}

static void ic_normalize_fmt(struct v4l2_pix_format *pix)
{
	const struct v4l2_frmsize_discrete *size;

	size = v4l2_find_nearest_size(ic_sizes, ARRAY_SIZE(ic_sizes), width, height,
				      pix->width, pix->height);
	*pix = (struct v4l2_pix_format) {
		.width = size->width,
		.height = size->height,
		.pixelformat = V4L2_PIX_FMT_YUYV,
		.field = V4L2_FIELD_NONE,
		.bytesperline = size->width * 2,
		.sizeimage = size->width * size->height * 2,
		.colorspace = V4L2_COLORSPACE_REC709,
		.ycbcr_enc = V4L2_YCBCR_ENC_709,
		.quantization = V4L2_QUANTIZATION_LIM_RANGE,
		.xfer_func = V4L2_XFER_FUNC_709,
	};
}

static int ic_try_fmt(struct file *file, void *priv, struct v4l2_format *format)
{
	ic_normalize_fmt(&format->fmt.pix);
	return 0;
}

static int ic_get_fmt(struct file *file, void *priv, struct v4l2_format *format)
{
	struct ic_capture *cap = video_drvdata(file);

	format->fmt.pix = cap->format;
	return 0;
}

static int ic_set_fmt(struct file *file, void *priv, struct v4l2_format *format)
{
	struct ic_capture *cap = video_drvdata(file);

	if (vb2_is_busy(&cap->queue))
		return -EBUSY;
	ic_normalize_fmt(&format->fmt.pix);
	cap->format = format->fmt.pix;
	return 0;
}

static int ic_enum_framesizes(struct file *file, void *priv, struct v4l2_frmsizeenum *size)
{
	if (size->index >= ARRAY_SIZE(ic_sizes) || size->pixel_format != V4L2_PIX_FMT_YUYV)
		return -EINVAL;
	size->type = V4L2_FRMSIZE_TYPE_DISCRETE;
	size->discrete = ic_sizes[size->index];
	return 0;
}

static int ic_enum_input(struct file *file, void *priv, struct v4l2_input *input)
{
	struct ic_capture *cap = video_drvdata(file);

	if (input->index > IC_INPUT_PATTERN)
		return -EINVAL;
	input->type = V4L2_INPUT_TYPE_CAMERA;
	if (input->index == IC_INPUT_SENSOR) {
		strscpy(input->name, "PCAM sensor", sizeof(input->name));
		if (!cap->sensor)
			input->status = V4L2_IN_ST_NO_SIGNAL;
	} else {
		strscpy(input->name, "IronCapture pattern", sizeof(input->name));
	}
	return 0;
}

static int ic_get_input(struct file *file, void *priv, unsigned int *input)
{
	struct ic_capture *cap = video_drvdata(file);

	*input = cap->input;
	return 0;
}

static int ic_set_input(struct file *file, void *priv, unsigned int input)
{
	struct ic_capture *cap = video_drvdata(file);

	if (input > IC_INPUT_PATTERN)
		return -EINVAL;
	if (vb2_is_busy(&cap->queue))
		return -EBUSY;
	cap->input = input;
	return 0;
}

static const struct v4l2_ioctl_ops ic_ioctl_ops = {
	.vidioc_querycap = ic_querycap,
	.vidioc_enum_fmt_vid_cap = ic_enum_fmt,
	.vidioc_g_fmt_vid_cap = ic_get_fmt,
	.vidioc_s_fmt_vid_cap = ic_set_fmt,
	.vidioc_try_fmt_vid_cap = ic_try_fmt,
	.vidioc_enum_framesizes = ic_enum_framesizes,
	.vidioc_enum_input = ic_enum_input,
	.vidioc_g_input = ic_get_input,
	.vidioc_s_input = ic_set_input,
	.vidioc_reqbufs = vb2_ioctl_reqbufs,
	.vidioc_create_bufs = vb2_ioctl_create_bufs,
	.vidioc_querybuf = vb2_ioctl_querybuf,
	.vidioc_expbuf = vb2_ioctl_expbuf,
	.vidioc_prepare_buf = vb2_ioctl_prepare_buf,
	.vidioc_qbuf = vb2_ioctl_qbuf,
	.vidioc_dqbuf = vb2_ioctl_dqbuf,
	.vidioc_streamon = vb2_ioctl_streamon,
	.vidioc_streamoff = vb2_ioctl_streamoff,
};

static const struct v4l2_file_operations ic_file_ops = {
	.owner = THIS_MODULE,
	.open = v4l2_fh_open,
	.release = vb2_fop_release,
	.unlocked_ioctl = video_ioctl2,
	.poll = vb2_fop_poll,
	.mmap = vb2_fop_mmap,
};

static int ic_sensor_bound(struct v4l2_async_notifier *notifier,
			   struct v4l2_subdev *sensor, struct v4l2_async_connection *asc)
{
	struct ic_capture *cap = container_of(notifier, struct ic_capture, notifier);

	mutex_lock(&cap->lock);
	cap->sensor = sensor;
	mutex_unlock(&cap->lock);
	return 0;
}

static void ic_sensor_unbind(struct v4l2_async_notifier *notifier,
			     struct v4l2_subdev *sensor, struct v4l2_async_connection *asc)
{
	struct ic_capture *cap = container_of(notifier, struct ic_capture, notifier);

	mutex_lock(&cap->lock);
	if (cap->sensor_streaming) {
		ic_drain(cap);
		cap->sensor_streaming = false;
		ic_return_buffers(cap, VB2_BUF_STATE_ERROR);
		vb2_queue_error(&cap->queue);
	}
	cap->sensor = NULL;
	mutex_unlock(&cap->lock);
}

static const struct v4l2_async_notifier_operations ic_notifier_ops = {
	.bound = ic_sensor_bound,
	.unbind = ic_sensor_unbind,
};

static int ic_sensor_discover(struct ic_capture *cap)
{
	struct v4l2_async_connection *connection;
	struct fwnode_handle *endpoint;

	v4l2_async_nf_init(&cap->notifier, &cap->v4l2);
	cap->notifier.ops = &ic_notifier_ops;
	endpoint = fwnode_graph_get_next_endpoint(dev_fwnode(cap->dev), NULL);
	if (!endpoint) {
		cap->input = IC_INPUT_PATTERN;
		return 0;
	}
	connection = v4l2_async_nf_add_fwnode_remote(&cap->notifier, endpoint,
						     struct v4l2_async_connection);
	fwnode_handle_put(endpoint);
	if (IS_ERR(connection))
		return PTR_ERR(connection);
	return v4l2_async_nf_register(&cap->notifier);
}

static void ic_release(struct v4l2_device *v4l2)
{
	struct ic_capture *cap = container_of(v4l2, struct ic_capture, v4l2);

	put_device(cap->dev);
	kfree(cap);
}

static int ic_probe_platform(struct platform_device *pdev)
{
	struct ic_capture *cap;
	unsigned int tune_properties;
	int ret;

	cap = kzalloc_obj(*cap);
	if (!cap)
		return -ENOMEM;
	cap->dev = get_device(&pdev->dev);
	cap->hw = (struct ic_device) {
		.context = cap,
		.read = ic_read_reg,
		.write = ic_write_reg,
	};
	mutex_init(&cap->lock);
	spin_lock_init(&cap->dma_lock);
	INIT_LIST_HEAD(&cap->pending);
	cap->format.width = ic_sizes[0].width;
	cap->format.height = ic_sizes[0].height;
	ic_normalize_fmt(&cap->format);
	cap->registers = devm_platform_ioremap_resource(pdev, 0);
	if (IS_ERR(cap->registers)) {
		ret = PTR_ERR(cap->registers);
		goto free;
	}
	if (ic_probe(&cap->hw)) {
		ret = -ENODEV;
		goto free;
	}
	ic_stop(&cap->hw);
	ic_ack(&cap->hw);
	tune_properties = !!device_property_present(cap->dev, "ironkernel,rx-taps0") +
			  !!device_property_present(cap->dev, "ironkernel,rx-taps1") +
			  !!device_property_present(cap->dev, "ironkernel,rx-phase");
	if (tune_properties) {
		if (tune_properties != 3 ||
		    device_property_read_u32(cap->dev, "ironkernel,rx-taps0", &cap->taps0) ||
		    device_property_read_u32(cap->dev, "ironkernel,rx-taps1", &cap->taps1) ||
		    device_property_read_u32(cap->dev, "ironkernel,rx-phase", &cap->phase)) {
			ret = -EINVAL;
			goto free;
		}
		cap->tune = true;
	}
	cap->bit_reverse = device_property_read_bool(cap->dev, "ironkernel,rx-bit-reverse");
	ret = dma_set_mask_and_coherent(cap->dev, DMA_BIT_MASK(32));
	if (ret)
		goto free;
	cap->irq = platform_get_irq(pdev, 0);
	if (cap->irq < 0) {
		ret = cap->irq;
		goto free;
	}
	ret = request_irq(cap->irq, ic_interrupt, 0, dev_name(cap->dev), cap);
	if (ret)
		goto free;
	ic_drain(cap);
	ret = v4l2_device_register(cap->dev, &cap->v4l2);
	if (ret)
		goto free_irq;
	cap->v4l2.release = ic_release;
	platform_set_drvdata(pdev, cap);
	cap->queue = (struct vb2_queue) {
		.type = V4L2_BUF_TYPE_VIDEO_CAPTURE,
		.io_modes = VB2_MMAP,
		.ops = &ic_queue_ops,
		.mem_ops = &vb2_dma_contig_memops,
		.drv_priv = cap,
		.buf_struct_size = sizeof(struct ic_buffer),
		.timestamp_flags = V4L2_BUF_FLAG_TIMESTAMP_MONOTONIC,
		.min_queued_buffers = 1,
		.dev = cap->dev,
		.lock = &cap->lock,
	};
	ret = vb2_queue_init(&cap->queue);
	if (ret)
		goto unregister_v4l2;
	ret = ic_sensor_discover(cap);
	if (ret)
		goto cleanup_notifier;
	strscpy(cap->video.name, "IronCapture", sizeof(cap->video.name));
	cap->video.v4l2_dev = &cap->v4l2;
	cap->video.fops = &ic_file_ops;
	cap->video.ioctl_ops = &ic_ioctl_ops;
	cap->video.release = video_device_release_empty;
	cap->video.lock = &cap->lock;
	cap->video.queue = &cap->queue;
	cap->video.device_caps = V4L2_CAP_VIDEO_CAPTURE | V4L2_CAP_STREAMING;
	video_set_drvdata(&cap->video, cap);
	ret = video_register_device(&cap->video, VFL_TYPE_VIDEO, -1);
	if (!ret)
		return 0;
	v4l2_async_nf_unregister(&cap->notifier);
cleanup_notifier:
	v4l2_async_nf_cleanup(&cap->notifier);
	vb2_queue_release(&cap->queue);
unregister_v4l2:
	platform_set_drvdata(pdev, NULL);
	v4l2_device_unregister(&cap->v4l2);
free_irq:
	free_irq(cap->irq, cap);
free:
	ic_release(&cap->v4l2);
	return ret;
}

static void ic_remove_platform(struct platform_device *pdev)
{
	struct ic_capture *cap = platform_get_drvdata(pdev);

	vb2_video_unregister_device(&cap->video);
	v4l2_async_nf_unregister(&cap->notifier);
	v4l2_async_nf_cleanup(&cap->notifier);
	ic_drain(cap);
	free_irq(cap->irq, cap);
	platform_set_drvdata(pdev, NULL);
	v4l2_device_unregister(&cap->v4l2);
	v4l2_device_put(&cap->v4l2);
}

static ssize_t capture_stats_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	struct ic_capture *cap = dev_get_drvdata(dev);
	unsigned long flags;
	u64 frames, bytes, errors;
	bool running;

	spin_lock_irqsave(&cap->dma_lock, flags);
	frames = cap->completed_frames;
	bytes = cap->completed_bytes;
	errors = cap->dma_errors;
	running = cap->running;
	spin_unlock_irqrestore(&cap->dma_lock, flags);
	return sysfs_emit(buf, "running %u\nframes %llu\npayload_bytes %llu\ndma_errors %llu\n",
			  running, frames, bytes, errors);
}
static DEVICE_ATTR_RO(capture_stats);
static struct attribute *ic_attrs[] = { &dev_attr_capture_stats.attr, NULL };
ATTRIBUTE_GROUPS(ic);

static const struct of_device_id ic_of_match[] = {
	{ .compatible = "ironkernel,ironcapture-1.0" },
	{}
};
MODULE_DEVICE_TABLE(of, ic_of_match);

static struct platform_driver ic_platform_driver = {
	.probe = ic_probe_platform,
	.remove = ic_remove_platform,
	.driver = {
		.name = "ironcapture",
		.of_match_table = ic_of_match,
		.dev_groups = ic_groups,
	},
};
module_platform_driver(ic_platform_driver);

MODULE_DESCRIPTION("IronKernel IronCapture V4L2 driver");
MODULE_LICENSE("GPL");
