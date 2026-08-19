/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "FreeRTOS.h"
#include "queue.h"
#include "semphr.h"
#include "task.h"

#include "eriscv_mcu.h"
#include "plic.h"
#include "timer.h"

#define MONITOR_EVENT_QUEUE_LEN 16u
#define MONITOR_QUEUE_EVENT 0x51455545u
#define MONITOR_BURST_EVENT 0x42555253u
#define MONITOR_SAMPLE_EVENT 0x53414d50u
#define MONITOR_DHRYSTONE_EVENT 0x44485259u
#define MONITOR_COREMARK_EVENT 0x434f5245u
#define MONITOR_TRACE_LEN 128u
#define MONITOR_WORKLOAD_IDLE 0u
#define MONITOR_WORKLOAD_DHRYSTONE 1u
#define MONITOR_WORKLOAD_COREMARK 2u
#ifndef FREERTOS_MONITOR_SAMPLE_RATE_HZ
#define FREERTOS_MONITOR_SAMPLE_RATE_HZ 1000u
#endif
#define MONITOR_SAMPLE_RATE_HZ FREERTOS_MONITOR_SAMPLE_RATE_HZ

typedef struct {
  eriscv_mcu_u32 kind;
  eriscv_mcu_u32 sequence;
  eriscv_mcu_u32 sample;
  eriscv_mcu_u32 issued_mcycle;
} monitor_event_t;

static StaticTask_t console_tcb;
static StackType_t console_stack[256u];
static StaticTask_t telemetry_tcb;
static StackType_t telemetry_stack[192u];
static StaticTask_t worker_tcb;
static StackType_t worker_stack[192u];
static StaticTask_t timer_tcb;
static StackType_t timer_stack[192u];
static StaticTask_t idle_tcb;
static StackType_t idle_stack[configMINIMAL_STACK_SIZE];
static StaticQueue_t event_queue_buffer;
static monitor_event_t event_queue_storage[MONITOR_EVENT_QUEUE_LEN];
static QueueHandle_t event_queue;
static StaticSemaphore_t uart_output_mutex_buffer;
static SemaphoreHandle_t uart_output_mutex;
static TaskHandle_t console_task;
static TaskHandle_t telemetry_task;
static TaskHandle_t worker_task;
static TaskHandle_t timer_task;

extern int eriscv_monitor_dhrystone_run(void);
extern int eriscv_monitor_coremark_run(void);
extern volatile unsigned int eriscv_dhrystone_result;
extern volatile unsigned int eriscv_dhrystone_cycles;
extern volatile unsigned int eriscv_coremark_result;
extern volatile unsigned int eriscv_coremark_cycles;

static volatile eriscv_mcu_u32 uart_irq_count;
static volatile eriscv_mcu_u32 timer_irq_count;
static volatile eriscv_mcu_u32 worker_event_count;
static volatile eriscv_mcu_u32 telemetry_tick_count;
static volatile eriscv_mcu_u32 pipeline_active;
static volatile eriscv_mcu_u32 pipeline_sample_irq_count;
static volatile eriscv_mcu_u32 pipeline_frame_count;
static volatile eriscv_mcu_u32 pipeline_drop_count;
static volatile eriscv_mcu_u32 pipeline_sequence;
static volatile eriscv_mcu_u32 pipeline_latency_last;
static volatile eriscv_mcu_u32 pipeline_latency_peak;
static volatile eriscv_mcu_u32 pipeline_checksum;
static volatile eriscv_mcu_u32 pipeline_fir_last;
static volatile eriscv_mcu_u32 pipeline_input_trace[MONITOR_TRACE_LEN];
static volatile eriscv_mcu_u32 pipeline_fir_trace[MONITOR_TRACE_LEN];
static volatile eriscv_mcu_u32 pipeline_trace_index;
static volatile eriscv_mcu_u32 burst_count;
static volatile eriscv_mcu_u32 burst_cycles;
static volatile eriscv_mcu_u32 workload_mode;
static volatile eriscv_mcu_u32 dhrystone_cycles;
static volatile eriscv_mcu_u32 dhrystone_pass;
static volatile eriscv_mcu_u32 coremark_cycles;
static volatile eriscv_mcu_u32 coremark_pass;
static volatile eriscv_mcu_u32 monitor_fault;
static volatile eriscv_mcu_u32 idle_cycles;
static volatile eriscv_mcu_u32 runtime_last_mcycle;
static volatile void *runtime_last_task;
static volatile void *idle_task;
static volatile eriscv_mcu_u32 runtime_started;
static eriscv_mcu_u32 status_last_mcycle;
static eriscv_mcu_u32 status_last_idle_cycles;

typedef struct {
  eriscv_mcu_u32 cycles;
  eriscv_mcu_u32 instret;
  eriscv_mcu_u32 branch_retired;
  eriscv_mcu_u32 branch_taken;
  eriscv_mcu_u32 control_transfer;
  eriscv_mcu_u32 ifetch_wait;
} monitor_hpm_profile_t;

static monitor_hpm_profile_t dhrystone_hpm;
static monitor_hpm_profile_t coremark_hpm;

extern char __eriscv_mcu_imem_base;
extern char __eriscv_mcu_imem_limit;
extern char __eriscv_mcu_dmem_base;
extern char __eriscv_mcu_dmem_limit;
extern char __bss_end;

static eriscv_mcu_u32 read_csr(const char *name) {
  eriscv_mcu_u32 value = 0u;

  if (name[0] == 'c') {
    __asm__ volatile ("csrr %0, mcycle" : "=r"(value));
  } else {
    __asm__ volatile ("csrr %0, minstret" : "=r"(value));
  }
  return value;
}

static eriscv_mcu_u32 read_hpmcounter(unsigned int counter) {
  eriscv_mcu_u32 value = 0u;

  switch (counter) {
    case 3u: __asm__ volatile ("csrr %0, mhpmcounter3" : "=r"(value)); break;
    case 4u: __asm__ volatile ("csrr %0, mhpmcounter4" : "=r"(value)); break;
    case 5u: __asm__ volatile ("csrr %0, mhpmcounter5" : "=r"(value)); break;
    default: __asm__ volatile ("csrr %0, mhpmcounter6" : "=r"(value)); break;
  }
  return value;
}

static void write_hpmcounter(unsigned int counter, eriscv_mcu_u32 value) {
  switch (counter) {
    case 3u: __asm__ volatile ("csrw mhpmcounter3, %0" :: "r"(value) : "memory"); break;
    case 4u: __asm__ volatile ("csrw mhpmcounter4, %0" :: "r"(value) : "memory"); break;
    case 5u: __asm__ volatile ("csrw mhpmcounter5, %0" :: "r"(value) : "memory"); break;
    default: __asm__ volatile ("csrw mhpmcounter6, %0" :: "r"(value) : "memory"); break;
  }
}

static void write_mhpmevent(unsigned int counter, eriscv_mcu_u32 value) {
  switch (counter) {
    case 3u: __asm__ volatile ("csrw mhpmevent3, %0" :: "r"(value) : "memory"); break;
    case 4u: __asm__ volatile ("csrw mhpmevent4, %0" :: "r"(value) : "memory"); break;
    case 5u: __asm__ volatile ("csrw mhpmevent5, %0" :: "r"(value) : "memory"); break;
    default: __asm__ volatile ("csrw mhpmevent6, %0" :: "r"(value) : "memory"); break;
  }
}

static void monitor_hpm_profile_begin(monitor_hpm_profile_t *profile) {
  write_mhpmevent(3u, 0u);
  write_mhpmevent(4u, 0u);
  write_mhpmevent(5u, 0u);
  write_mhpmevent(6u, 0u);
  write_hpmcounter(3u, 0u);
  write_hpmcounter(4u, 0u);
  write_hpmcounter(5u, 0u);
  write_hpmcounter(6u, 0u);
  write_mhpmevent(3u, 3u);  /* BRANCH_RETIRED */
  write_mhpmevent(4u, 4u);  /* BRANCH_TAKEN */
  write_mhpmevent(5u, 5u);  /* CONTROL_TRANSFER_RETIRED */
  write_mhpmevent(6u, 8u);  /* IFETCH_WAIT_CYCLES */
  profile->cycles = read_csr("cycle");
  profile->instret = read_csr("instret");
}

static void monitor_hpm_profile_end(monitor_hpm_profile_t *profile) {
  profile->cycles = read_csr("cycle") - profile->cycles;
  profile->instret = read_csr("instret") - profile->instret;
  write_mhpmevent(3u, 0u);
  write_mhpmevent(4u, 0u);
  write_mhpmevent(5u, 0u);
  write_mhpmevent(6u, 0u);
  profile->branch_retired = read_hpmcounter(3u);
  profile->branch_taken = read_hpmcounter(4u);
  profile->control_transfer = read_hpmcounter(5u);
  profile->ifetch_wait = read_hpmcounter(6u);
  write_mhpmevent(3u, 8u);  /* M0 reset/default profile */
  write_mhpmevent(4u, 9u);
  write_mhpmevent(5u, 4u);
  write_mhpmevent(6u, 7u);
}

static void uart_putc(char ch) {
  while (eriscv_mcu_uart_async_putc(ch) == 0) {
    /* Status lines can be larger than the software TX FIFO.  Yield while the
     * UART drains instead of consuming a full character time in a spin loop. */
    vTaskDelay(pdMS_TO_TICKS(1u));
  }
}

static void uart_puts(const char *text) {
  while (*text != '\0') {
    if (*text == '\n') {
      uart_putc('\r');
    }
    uart_putc(*text++);
  }
}

static void uart_put_u32(eriscv_mcu_u32 value) {
  char text[11];
  eriscv_mcu_u32 index = 0u;

  if (value == 0u) {
    uart_putc('0');
    return;
  }
  while (value != 0u) {
    text[index++] = (char)('0' + (value % 10u));
    value /= 10u;
  }
  while (index != 0u) {
    uart_putc(text[--index]);
  }
}

static void monitor_print_trace(const volatile eriscv_mcu_u32 *trace) {
  eriscv_mcu_u32 offset;

  for (offset = 0u; offset < MONITOR_TRACE_LEN; ++offset) {
    eriscv_mcu_u32 index = (pipeline_trace_index + offset) & (MONITOR_TRACE_LEN - 1u);

    if (offset != 0u) {
      uart_putc(',');
    }
    uart_put_u32(trace[index]);
  }
}

static void uart_output_lock(void) {
  configASSERT(xSemaphoreTake(uart_output_mutex, portMAX_DELAY) == pdPASS);
}

static void uart_output_unlock(void) {
  configASSERT(xSemaphoreGive(uart_output_mutex) == pdPASS);
}

static void monitor_print_workload(void) {
  if (workload_mode == MONITOR_WORKLOAD_DHRYSTONE) {
    uart_puts("dhrystone");
  } else if (workload_mode == MONITOR_WORKLOAD_COREMARK) {
    uart_puts("coremark");
  } else {
    uart_puts("idle");
  }
}

static void monitor_print_benchmark_done(const char *name) {
  uart_output_lock();
  uart_puts("@BENCH_DONE ");
  uart_puts(name);
  uart_puts("\n");
  uart_output_unlock();
}

static void monitor_print_hpm_profile(const char *prefix, const monitor_hpm_profile_t *profile) {
  eriscv_mcu_u32 redirects = profile->branch_taken + profile->control_transfer;

  uart_puts(" ");
  uart_puts(prefix);
  uart_puts("_hpm_cycles=");
  uart_put_u32(profile->cycles);
  uart_puts(" ");
  uart_puts(prefix);
  uart_puts("_hpm_instret=");
  uart_put_u32(profile->instret);
  uart_puts(" ");
  uart_puts(prefix);
  uart_puts("_branches=");
  uart_put_u32(profile->branch_retired);
  uart_puts(" ");
  uart_puts(prefix);
  uart_puts("_taken=");
  uart_put_u32(profile->branch_taken);
  uart_puts(" ");
  uart_puts(prefix);
  uart_puts("_control=");
  uart_put_u32(profile->control_transfer);
  uart_puts(" ");
  uart_puts(prefix);
  uart_puts("_ifetch_wait=");
  uart_put_u32(profile->ifetch_wait);
  uart_puts(" ");
  uart_puts(prefix);
  uart_puts("_redirects=");
  uart_put_u32(redirects);
  uart_puts(" ");
  uart_puts(prefix);
  uart_puts("_flush_slots=");
  uart_put_u32(redirects * 2u);
}

static void uart_put_task(const char *name, TaskHandle_t task, eriscv_mcu_u32 priority) {
  uart_puts("task name=");
  uart_puts(name);
  uart_puts(" prio=");
  uart_put_u32(priority);
  uart_puts(" stack_free_words=");
  uart_put_u32((eriscv_mcu_u32)uxTaskGetStackHighWaterMark(task));
  uart_puts("\n");
}

static void monitor_print_status(void) {
  eriscv_mcu_u32 mcycle = read_csr("cycle");
  eriscv_mcu_u32 idle = idle_cycles;
  eriscv_mcu_u32 elapsed = mcycle - status_last_mcycle;
  eriscv_mcu_u32 idle_elapsed = idle - status_last_idle_cycles;
  eriscv_mcu_u32 cpu_permille = 0u;
  eriscv_mcu_u32 cpu_basis_points = 0u;
  eriscv_mcu_u32 busy_cycles = 0u;
  eriscv_mcu_u32 imem_bytes = (eriscv_mcu_u32)(&__eriscv_mcu_imem_limit - &__eriscv_mcu_imem_base);
  eriscv_mcu_u32 dmem_bytes = (eriscv_mcu_u32)(&__eriscv_mcu_dmem_limit - &__eriscv_mcu_dmem_base);
  eriscv_mcu_u32 dmem_static = (eriscv_mcu_u32)(&__bss_end - &__eriscv_mcu_dmem_base);

  if (status_last_mcycle != 0u && idle_elapsed <= elapsed && elapsed != 0u) {
    busy_cycles = elapsed - idle_elapsed;
    cpu_basis_points = (eriscv_mcu_u32)(((unsigned long long)busy_cycles * 10000u) / elapsed);
    cpu_permille = cpu_basis_points / 10u;
  }
  status_last_mcycle = mcycle;
  status_last_idle_cycles = idle;

  uart_puts("@STAT cpu_permille=");
  uart_put_u32(cpu_permille);
  uart_puts(" cpu_basis_points=");
  uart_put_u32(cpu_basis_points);
  uart_puts(" mcycle=");
  uart_put_u32(mcycle);
  uart_puts(" minstret=");
  uart_put_u32(read_csr("instret"));
  uart_puts(" tasks=5");
  uart_puts(" heap_free=");
  uart_put_u32((eriscv_mcu_u32)xPortGetFreeHeapSize());
  uart_puts(" heap_min=");
  uart_put_u32((eriscv_mcu_u32)xPortGetMinimumEverFreeHeapSize());
  uart_puts(" imem_bytes=");
  uart_put_u32(imem_bytes);
  uart_puts(" dmem_bytes=");
  uart_put_u32(dmem_bytes);
  uart_puts(" dmem_static=");
  uart_put_u32(dmem_static);
  uart_puts(" uart_irq=");
  uart_put_u32(uart_irq_count);
  uart_puts(" uart_drop=");
  uart_put_u32(eriscv_mcu_uart_async_rx_dropped());
  uart_puts(" timer_irq=");
  uart_put_u32(timer_irq_count);
  uart_puts(" worker_events=");
  uart_put_u32(worker_event_count);
  uart_puts(" telemetry_ticks=");
  uart_put_u32(telemetry_tick_count);
  uart_puts(" pipeline_active=");
  uart_put_u32(pipeline_active);
  uart_puts(" sample_irq=");
  uart_put_u32(pipeline_sample_irq_count);
  uart_puts(" frames=");
  uart_put_u32(pipeline_frame_count);
  uart_puts(" drops=");
  uart_put_u32(pipeline_drop_count);
  uart_puts(" latency_last=");
  uart_put_u32(pipeline_latency_last);
  uart_puts(" latency_peak=");
  uart_put_u32(pipeline_latency_peak);
  uart_puts(" checksum=");
  uart_put_u32(pipeline_checksum);
  uart_puts(" fir_last=");
  uart_put_u32(pipeline_fir_last);
  if (pipeline_active != 0u) {
    uart_puts(" input_trace=");
    monitor_print_trace(pipeline_input_trace);
    uart_puts(" fir_trace=");
    monitor_print_trace(pipeline_fir_trace);
  }
  uart_puts(" burst_count=");
  uart_put_u32(burst_count);
  uart_puts(" burst_cycles=");
  uart_put_u32(burst_cycles);
  uart_puts(" workload=");
  monitor_print_workload();
  uart_puts(" dhrystone_cycles=");
  uart_put_u32(dhrystone_cycles);
  uart_puts(" dhrystone_pass=");
  uart_put_u32(dhrystone_pass);
  monitor_print_hpm_profile("dhrystone", &dhrystone_hpm);
  uart_puts(" coremark_cycles=");
  uart_put_u32(coremark_cycles);
  uart_puts(" coremark_pass=");
  uart_put_u32(coremark_pass);
  monitor_print_hpm_profile("coremark", &coremark_hpm);
  uart_puts("\n");
}

static void monitor_print_tasks(void) {
  uart_puts("tasks=5 static-profile\n");
  uart_put_task("console", console_task, 2u);
  uart_put_task("worker", worker_task, 3u);
  uart_put_task("timer", timer_task, 1u);
  uart_put_task("telemetry", telemetry_task, 0u);
}

static void monitor_print_help(void) {
  uart_puts("commands: help info status tasks queue timer stream burst dhrystone coremark\n");
}

static void monitor_print_info(void) {
  uart_puts("eRISCV-M0 FreeRTOS monitor cpu_hz=");
  uart_put_u32((eriscv_mcu_u32)ERISCV_MONITOR_CPU_HZ);
  uart_puts(" uart_div=");
  uart_put_u32(ERISCV_MONITOR_UART_DIV);
  uart_puts(" imem=32768 dmem=32768 sample_hz=");
  uart_put_u32(MONITOR_SAMPLE_RATE_HZ);
  uart_puts("\n");
}

static void monitor_dispatch(const char *line) {
  eriscv_mcu_u32 trace_index;
  monitor_event_t event = {
      .kind = MONITOR_QUEUE_EVENT,
      .sequence = 0u,
      .sample = 0u,
      .issued_mcycle = read_csr("cycle"),
  };

  if (line[0] == 'h') {
    monitor_print_help();
  } else if (line[0] == 'i') {
    monitor_print_info();
  } else if (line[0] == 's' || line[0] == 'S') {
    monitor_print_status();
  } else if (line[0] == 't') {
    monitor_print_tasks();
  } else if (line[0] == 'm') {
    monitor_print_status();
  } else if (line[0] == 'e') {
    uart_puts("echo enabled\n");
  } else if (line[0] == 'q') {
    if (xQueueSend(event_queue, &event, 0u) == pdPASS) {
      uart_puts("queue event accepted\n");
    } else {
      uart_puts("queue busy\n");
    }
  } else if (line[0] == 'r') {
    if (pipeline_active != 0u) {
      uart_puts("timer owned by signal pipeline; stop stream first\n");
    } else {
      freertos_timer_start(ERISCV_MONITOR_TIMER_DELAY_CYCLES, 1);
      uart_puts("timer armed\n");
    }
  } else if (line[0] == 'w') {
    if (workload_mode != MONITOR_WORKLOAD_IDLE) {
      uart_puts("benchmark running; wait for completion\n");
    } else if (pipeline_active == 0u) {
      pipeline_active = 1u;
      pipeline_sample_irq_count = 0u;
      pipeline_frame_count = 0u;
      pipeline_drop_count = 0u;
      pipeline_sequence = 0u;
      pipeline_latency_last = 0u;
      pipeline_latency_peak = 0u;
      pipeline_checksum = 0u;
      pipeline_fir_last = 0u;
      pipeline_trace_index = 0u;
      for (trace_index = 0u; trace_index < MONITOR_TRACE_LEN; ++trace_index) {
        pipeline_input_trace[trace_index] = 512u;
        pipeline_fir_trace[trace_index] = 512u;
      }
      freertos_timer_start(ERISCV_MONITOR_CPU_HZ / MONITOR_SAMPLE_RATE_HZ, 1);
      uart_puts("signal pipeline started: Timer0 -> PLIC -> queue -> FIR\n");
    } else {
      pipeline_active = 0u;
      freertos_timer_stop();
      uart_puts("signal pipeline stopped\n");
    }
  } else if (line[0] == 'b') {
    event.kind = MONITOR_BURST_EVENT;
    if (xQueueSend(event_queue, &event, 0u) == pdPASS) {
      uart_puts("compute burst queued\n");
    } else {
      uart_puts("queue busy\n");
    }
  } else if (line[0] == 'd' || line[0] == 'c') {
    if (workload_mode != MONITOR_WORKLOAD_IDLE) {
      uart_puts("benchmark running; wait for completion\n");
    } else {
      if (pipeline_active != 0u) {
        pipeline_active = 0u;
        freertos_timer_stop();
        uart_puts("signal pipeline stopped for benchmark\n");
      }
      if (line[0] == 'd') {
        event.kind = MONITOR_DHRYSTONE_EVENT;
        workload_mode = MONITOR_WORKLOAD_DHRYSTONE;
        uart_puts("Dhrystone monitor-mode run started\n");
      } else {
        event.kind = MONITOR_COREMARK_EVENT;
        workload_mode = MONITOR_WORKLOAD_COREMARK;
        uart_puts("CoreMark monitor-mode smoke started\n");
      }
      if (xQueueSend(event_queue, &event, 0u) != pdPASS) {
        workload_mode = MONITOR_WORKLOAD_IDLE;
        uart_puts("queue busy\n");
      }
    }
  } else {
    uart_puts("unknown command; type help\n");
  }
}

static void console_task_entry(void *argument) {
  char command[2];

  (void)argument;
  /* Do not enable external interrupts until the scheduler has selected this
   * task and its notification target is valid. */
  eriscv_mcu_uart_async_init(ERISCV_MONITOR_UART_DIV);
  uart_output_lock();
  uart_puts("eRISCV-M0 FreeRTOS monitor\n");
  monitor_print_help();
  uart_puts("> ");
  uart_output_unlock();
  for (;;) {
    int byte;

    (void)ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    while ((byte = eriscv_mcu_uart_async_getc()) >= 0) {
      if (byte >= 0x20 && byte <= 0x7e) {
        int silent_status = (byte == 'S');

        command[0] = (char)byte;
        command[1] = '\0';
        uart_output_lock();
        if (!silent_status) {
          uart_putc((char)byte);
          uart_puts("\n");
        }
        monitor_dispatch(command);
        if (!silent_status) {
          uart_puts("> ");
        }
        uart_output_unlock();
      }
    }
  }
}

static void telemetry_task_entry(void *argument) {
  (void)argument;
  for (;;) {
    vTaskDelay(pdMS_TO_TICKS(1000u));
    ++telemetry_tick_count;
  }
}

static void pipeline_process_sample(const monitor_event_t *event) {
  static const int coefficients[32] = {
      1, 2, 3, 4, 5, 6, 7, 8,
      9, 10, 11, 12, 13, 14, 15, 16,
      16, 15, 14, 13, 12, 11, 10, 9,
      8, 7, 6, 5, 4, 3, 2, 1,
  };
  static int history[32];
  eriscv_mcu_u32 index = event->sequence & 31u;
  eriscv_mcu_u32 tap;
  int accumulator = 0;
  eriscv_mcu_u32 filtered;
  eriscv_mcu_u32 latency;

  history[index] = (int)(event->sample & 0x3ffu) - 512;
  for (tap = 0u; tap < 32u; ++tap) {
    accumulator += history[(index - tap) & 31u] * coefficients[tap];
  }
  latency = read_csr("cycle") - event->issued_mcycle;
  pipeline_latency_last = latency;
  if (latency > pipeline_latency_peak) {
    pipeline_latency_peak = latency;
  }
  pipeline_checksum = (pipeline_checksum << 5) ^ (pipeline_checksum >> 2) ^
                      (eriscv_mcu_u32)accumulator ^ event->sequence;
  filtered = (eriscv_mcu_u32)(accumulator / 256 + 512);
  pipeline_fir_last = filtered;
  pipeline_input_trace[pipeline_trace_index] = event->sample;
  pipeline_fir_trace[pipeline_trace_index] = filtered;
  pipeline_trace_index = (pipeline_trace_index + 1u) & (MONITOR_TRACE_LEN - 1u);
  ++pipeline_frame_count;
}

static eriscv_mcu_u32 pipeline_next_sample(eriscv_mcu_u32 sequence) {
  static const int cosine_lut[64] = {
      240, 239, 235, 230, 222, 212, 200, 186,
      170, 152, 133, 113, 92, 70, 47, 24,
      0, -24, -47, -70, -92, -113, -133, -152,
      -170, -186, -200, -212, -222, -230, -235, -239,
      -240, -239, -235, -230, -222, -212, -200, -186,
      -170, -152, -133, -113, -92, -70, -47, -24,
      0, 24, 47, 70, 92, 113, 133, 152,
      170, 186, 200, 212, 222, 230, 235, 239,
  };
  int sample = 512 + cosine_lut[sequence & 63u];

  /* A Nyquist-rate disturbance. The symmetric 32-tap FIR rejects it while
   * retaining the lower-frequency cosine component. */
  sample += ((sequence & 1u) == 0u) ? 96 : -96;
  return (eriscv_mcu_u32)sample;
}

static void pipeline_run_burst(void) {
  eriscv_mcu_u32 start = read_csr("cycle");
  eriscv_mcu_u32 value = pipeline_checksum ^ 0x6d2b79f5u;
  eriscv_mcu_u32 index;

  for (index = 0u; index < 4096u; ++index) {
    value ^= value << 13;
    value ^= value >> 17;
    value ^= value << 5;
    value += index ^ 0x9e3779b9u;
  }
  pipeline_checksum ^= value;
  burst_cycles = read_csr("cycle") - start;
  ++burst_count;
}

static void worker_task_entry(void *argument) {
  monitor_event_t event;

  (void)argument;
  for (;;) {
    if (xQueueReceive(event_queue, &event, portMAX_DELAY) != pdPASS) {
      continue;
    }
    if (event.kind == MONITOR_SAMPLE_EVENT) {
      pipeline_process_sample(&event);
    } else if (event.kind == MONITOR_BURST_EVENT) {
      pipeline_run_burst();
    } else if (event.kind == MONITOR_QUEUE_EVENT) {
      ++worker_event_count;
      uart_output_lock();
      uart_puts("demo queue consumed\n");
      uart_output_unlock();
    } else if (event.kind == MONITOR_DHRYSTONE_EVENT) {
      monitor_hpm_profile_begin(&dhrystone_hpm);
      (void)eriscv_monitor_dhrystone_run();
      monitor_hpm_profile_end(&dhrystone_hpm);
      dhrystone_cycles = eriscv_dhrystone_cycles;
      dhrystone_pass = (eriscv_dhrystone_result & 0x80000000u) != 0u;
      workload_mode = MONITOR_WORKLOAD_IDLE;
      monitor_print_benchmark_done("dhrystone");
    } else if (event.kind == MONITOR_COREMARK_EVENT) {
      monitor_hpm_profile_begin(&coremark_hpm);
      (void)eriscv_monitor_coremark_run();
      monitor_hpm_profile_end(&coremark_hpm);
      coremark_cycles = eriscv_coremark_cycles;
      coremark_pass = (eriscv_coremark_result & 0x80000000u) != 0u;
      workload_mode = MONITOR_WORKLOAD_IDLE;
      monitor_print_benchmark_done("coremark");
    }
  }
}

static void timer_task_entry(void *argument) {
  (void)argument;
  for (;;) {
    (void)ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    uart_output_lock();
    uart_puts("demo timer wake\n");
    uart_output_unlock();
  }
}

static void drain_boot_uart_residue(void) {
  while ((eriscv_mcu_mmio_read32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_STATUS) &
          ERISCV_MCU_UART_STATUS_RX_VALID) != 0u) {
    (void)eriscv_mcu_mmio_read32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_RXDATA);
  }
}

void vAssertCalled(const char *file, unsigned long line) {
  (void)file;
  (void)line;
  monitor_fault = 1u;
  for (;;) {
  }
}

void vApplicationStackOverflowHook(TaskHandle_t task, char *task_name) {
  (void)task;
  (void)task_name;
  vAssertCalled(__FILE__, __LINE__);
}

void freertos_monitor_task_switched_in(void *task) {
  eriscv_mcu_u32 now = read_csr("cycle");

  if (runtime_started != 0u && runtime_last_task == idle_task) {
    idle_cycles += now - runtime_last_mcycle;
  }
  runtime_last_mcycle = now;
  runtime_last_task = task;
  runtime_started = 1u;
}

void vApplicationIdleHook(void) {
  if (idle_task == 0) {
    idle_task = (void *)xTaskGetIdleTaskHandle();
  }
}

void vApplicationGetIdleTaskMemory(StaticTask_t **tcb, StackType_t **stack,
                                   configSTACK_DEPTH_TYPE *stack_size) {
  *tcb = &idle_tcb;
  *stack = idle_stack;
  *stack_size = configMINIMAL_STACK_SIZE;
}

void freertos_risc_v_application_exception_handler(void) {
  vAssertCalled(__FILE__, __LINE__);
}

void freertos_risc_v_application_interrupt_handler(void) {
  eriscv_mcu_u32 mcause;
  eriscv_mcu_u32 source;
  BaseType_t task_woken = pdFALSE;

  __asm__ volatile ("csrr %0, mcause" : "=r"(mcause));
  if ((mcause & ERISCV_MCU_MCAUSE_CODE_MASK) != ERISCV_MCU_MCAUSE_MEI) {
    vAssertCalled(__FILE__, __LINE__);
  }
  source = freertos_plic_claim();
  if (source == ERISCV_MCU_UART0_PLIC_SOURCE) {
    ++uart_irq_count;
    eriscv_mcu_uart_irq_handler();
    vTaskNotifyGiveFromISR(console_task, &task_woken);
  } else if (source == ERISCV_MCU_TIMER0_PLIC_SOURCE) {
    monitor_event_t event;

    ++timer_irq_count;
    freertos_timer_stop();
    if (pipeline_active != 0u) {
      event.kind = MONITOR_SAMPLE_EVENT;
      event.sequence = pipeline_sequence++;
      event.sample = pipeline_next_sample(event.sequence);
      event.issued_mcycle = read_csr("cycle");
      ++pipeline_sample_irq_count;
      if (xQueueSendFromISR(event_queue, &event, &task_woken) != pdPASS) {
        ++pipeline_drop_count;
      }
      freertos_timer_start(ERISCV_MONITOR_CPU_HZ / MONITOR_SAMPLE_RATE_HZ, 1);
    } else {
      vTaskNotifyGiveFromISR(timer_task, &task_woken);
    }
  } else {
    vAssertCalled(__FILE__, __LINE__);
  }
  freertos_plic_complete(source);
  portYIELD_FROM_ISR(task_woken);
}

int main(void) {
  extern void freertos_risc_v_trap_handler(void);
  eriscv_mcu_u32 trace_index;

  __asm__ volatile ("csrw mtvec, %0" :: "r"(freertos_risc_v_trap_handler));
  eriscv_mcu_uart_init(ERISCV_MONITOR_UART_DIV);
  drain_boot_uart_residue();
  uart_irq_count = 0u;
  timer_irq_count = 0u;
  worker_event_count = 0u;
  telemetry_tick_count = 0u;
  pipeline_active = 0u;
  pipeline_sample_irq_count = 0u;
  pipeline_frame_count = 0u;
  pipeline_drop_count = 0u;
  pipeline_sequence = 0u;
  pipeline_latency_last = 0u;
  pipeline_latency_peak = 0u;
  pipeline_checksum = 0u;
  pipeline_fir_last = 0u;
  pipeline_trace_index = 0u;
  for (trace_index = 0u; trace_index < MONITOR_TRACE_LEN; ++trace_index) {
    pipeline_input_trace[trace_index] = 512u;
    pipeline_fir_trace[trace_index] = 512u;
  }
  burst_count = 0u;
  burst_cycles = 0u;
  workload_mode = MONITOR_WORKLOAD_IDLE;
  dhrystone_cycles = 0u;
  dhrystone_pass = 0u;
  coremark_cycles = 0u;
  coremark_pass = 0u;
  monitor_fault = 0u;
  idle_cycles = 0u;
  runtime_last_mcycle = 0u;
  runtime_last_task = 0;
  idle_task = 0;
  runtime_started = 0u;
  status_last_mcycle = read_csr("cycle");
  status_last_idle_cycles = 0u;
  event_queue = xQueueCreateStatic(MONITOR_EVENT_QUEUE_LEN, sizeof(event_queue_storage[0]),
                                   (unsigned char *)event_queue_storage, &event_queue_buffer);
  configASSERT(event_queue != 0);
  uart_output_mutex = xSemaphoreCreateMutexStatic(&uart_output_mutex_buffer);
  configASSERT(uart_output_mutex != 0);

  console_task = xTaskCreateStatic(console_task_entry, "console", 256u, 0, 2u,
                                    console_stack, &console_tcb);
  configASSERT(console_task != 0);
  telemetry_task = xTaskCreateStatic(telemetry_task_entry, "telemetry", 192u, 0, 0u,
                                      telemetry_stack, &telemetry_tcb);
  configASSERT(telemetry_task != 0);
  worker_task = xTaskCreateStatic(worker_task_entry, "worker", 192u, 0, 3u,
                                   worker_stack, &worker_tcb);
  configASSERT(worker_task != 0);
  timer_task = xTaskCreateStatic(timer_task_entry, "timer", 192u, 0, 1u,
                                 timer_stack, &timer_tcb);
  configASSERT(timer_task != 0);
  freertos_plic_init_source(ERISCV_MCU_TIMER0_PLIC_SOURCE, 1u);
  vTaskStartScheduler();
  vAssertCalled(__FILE__, __LINE__);
  return 1;
}
