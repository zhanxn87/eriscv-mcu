/*
 * eRISCV-MCU M0 SoC initialization
 * Copyright (c) 2024 eRISCV-MCU Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/init.h>
#include <zephyr/arch/cpu.h>
#include <zephyr/sys/sys_io.h>
#include <soc.h>

static int eriscv_mcu_m0_soc_init(void)
{
	if (IS_ENABLED(CONFIG_ERISCV_MCU_WFI_CLOCK_GATING)) {
		sys_write32(ERISCV_MCU_CLKRST_WFI_SLEEP_EN,
			    ERISCV_MCU_CLK_RST_BASE + ERISCV_MCU_CLKRST_SLEEP_CTRL);
	}
	return 0;
}

SYS_INIT(eriscv_mcu_m0_soc_init, PRE_KERNEL_1, 0);
