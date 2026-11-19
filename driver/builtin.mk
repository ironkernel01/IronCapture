# SPDX-License-Identifier: GPL-2.0-only
ironcapture_driver_dir := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

obj-$(CONFIG_VIDEO_IRONCAPTURE) += ironcapture.o
ironcapture-y := ironcapture_linux.o ironcapture_core.o

$(obj)/ironcapture_linux.o: $(ironcapture_driver_dir)/ironcapture_linux.c FORCE
	$(call if_changed_dep,cc_o_c)

$(obj)/ironcapture_core.o: $(ironcapture_driver_dir)/ironcapture.c FORCE
	$(call if_changed_dep,cc_o_c)
