# NovaLife RTOS Plan: a small kernel in Rust and C, for the PL enclave

> Status: **PROPOSAL.** Nothing here is built. Honesty rules from `AGENTS.md` apply: no speed,
> size or "beats FreeRTOS/RT-Thread" claim until it is measured with the protocol in section 6.

## 1. Purpose and where it runs

- **Product path stays on mature software:** Linux on the PS for the gateway, and for the enclave
  controller FreeRTOS (or bare metal) until our kernel passes the same tests.
- **Our RTOS runs as the enclave controller** on a VexRiscv soft-core in the PL, using only BRAM
  (small RAM, no DDR, no MMU). It sequences the mailbox commands, key custody, rate limiting and
  the marking pipeline. This is a real job with a small, checkable footprint.
- **Two goals, kept separate:** (1) *learn*: understand scheduling, interrupts, context switching
  and memory by writing a kernel twice (C and Rust); (2) *niche*: be better than FreeRTOS and
  RT-Thread at one narrow thing (section 3).

## 2. Decisions already made (and why)

| Decision | Reason |
|---|---|
| Not a fork or port of RT-Thread/FreeRTOS | A copy teaches little and is not "different"; both are studied for ideas only |
| Write the **kernel** ourselves; borrow everything else | Networking, TLS, file systems and drivers take years to mature; the kernel is the part worth learning |
| Rust and C implementations of the **same spec** | The course is embedded C; we want a fair comparison, not an opinion |
| Product does not depend on it until it passes the tests | Demo risk |
| The hub keeps **no listening sockets** | Smaller attack surface than any amount of kernel polish |

## 3. The niche (hypothesis to test, not a promise)

**A small RTOS for SoC-FPGA enclaves where hardware accelerators are first-class and safe to use.**
Concretely:

1. **Typed accelerator jobs.** A job (e.g. `MARK_IMAGE`) is a value: submit it, the buffer is
   *owned by the hardware* until the completion event, and the type system (Rust) or a checked API
   (C) stops the CPU touching it meanwhile. FreeRTOS has no accelerator model; RT-Thread has a
   device framework but no ownership rule for DMA buffers.
2. **Bounded, measured latency** from mailbox command to first accelerator word.
3. **Tiny, auditable footprint** in BRAM, with no heap in the core.

How the claim can **fail** (kill criteria, agreed before measuring):

- If the Rust build is not within an agreed margin of the C build on context-switch time and
  footprint, say so and keep C for the controller.
- If the typed-job API does not prevent a bug class that a seeded fault-injection test makes in the
  FreeRTOS version, there is no niche, only a smaller kernel.
- If neither beats FreeRTOS on a metric that matters to this product, the RTOS stays a learning
  project and the product uses FreeRTOS. That is an acceptable result.

## 4. Kernel scope (v0.x)

Spec first, one document, then two implementations that must pass the same tests:

- Fixed-priority preemptive scheduler, round robin within a priority, no dynamic allocation.
- Tick timer, delays, software timers.
- Mutex (with priority inheritance), binary and counting semaphore, bounded queue, event flags.
- Interrupt entry/exit, deferred work from interrupts.
- **Accelerator job queue** (the niche): submit, complete, timeout, cancel.
- Build target: **RV32IM** (the VexRiscv config: no atomics, so critical sections; check the
  compressed-instruction setting). In Rust verify the toolchain target for RV32IM early; if hardware
  atomics are missing use the `portable-atomic` approach or interrupt-disable sections.

Out of scope for v0: filesystem, networking, dynamic loading, SMP, shell.

## 5. Milestones and exit criteria

| # | Milestone | Exit criterion |
|---|---|---|
| E0 | **A real VexRiscv build exists.** Today `vexriscv_wrapper.v` is a stub and `hw/vexriscv_pl.bit` is a text placeholder. Generate VexRiscv (SpinalHDL or LiteX), wire BRAM and UART, bitstream it | "hello" over UART from RV32IM code on the board |
| M0 | Toolchains and simulator: C (`riscv32-unknown-elf-gcc`), Rust target, QEMU or Renode, test harness with pass/fail output | both compile "hello", run in the simulator |
| M1 | Boot, trap handler, tick timer, context switch (assembly), two tasks | tasks alternate; switch time read from the cycle counter |
| M2 | Scheduler with priorities, delays, mutex, semaphore, queue | shared test suite passes in C and in Rust |
| M3 | Accelerator job queue against a **software model** of the pipeline | job tests pass; seeded misuse caught or documented |
| M4 | On the board: mailbox from Linux (PS) to the kernel, real accelerator | end-to-end `BUILD_TAG` / `VERIFY_TAG` round trip |
| M5 | Benchmarks and comparison report (section 6) | table with medians and spread, same flags |
| M6 | Decide: Rust, C or FreeRTOS for the controller; freeze the other | decision recorded with the numbers |

From M3 on, keep C and Rust in lockstep only until M6; after that freeze the loser.

## 6. Comparison protocol (C vs Rust vs FreeRTOS, and RT-Thread Nano if feasible)

Same chip config, same clock, same compiler settings class (`-O2` or `-Os`, stated), same
configuration (priorities, tick rate), warm and cold runs, at least 30 runs, report min / median /
max, never a single number.

| Metric | How |
|---|---|
| Context-switch time | cycle counter around a yield between two tasks |
| Interrupt-to-task latency | toggle a PL pin in the ISR; measure with the logic analyser or an on-chip counter |
| Job submit-to-first-word latency | cycle counter from mailbox write to first accelerator output |
| Code and RAM footprint | `size` on the linked image, kernel only and with the test app |
| Worst-case jitter | max minus median under load |
| Bug classes | seeded faults (DMA buffer touched early, queue overrun, priority inversion) and what each kernel catches |

Never report results from the simulator as board results.

## 7. Learning path (Rust, with the C twin beside it)

Study order, one week per step as a guide:

1. Rust basics: ownership, borrowing, `Option/Result`, traits, `no_std` and `unsafe`
   (*The Rust Programming Language*, then *The Embedded Rust Book*).
2. RISC-V basics: privilege levels, CSRs (`mcycle`, `mstatus`, `mtvec`), traps, the calling
   convention (the RISC-V specs and the `riscv` crate sources).
3. OS from nothing: write a toy kernel for QEMU (the *Writing an OS in Rust* approach, adapted to
   RISC-V), then the same in C.
4. Read, do not copy: FreeRTOS `tasks.c` and the RISC-V port, RT-Thread Nano's scheduler, Tock,
   Hubris and Embassy design notes. Write down what each does differently.
5. Each milestone ends with a one-page "what I learned and what I got wrong" note in `docs/`.

## 8. Self-grill: where this plan can be wrong

| Challenge | Honest answer |
|---|---|
| "Why write an RTOS at all?" | Learning and one narrow niche. If the niche test fails we say so and use FreeRTOS. |
| "Will Rust beat C?" | Not on speed. Its possible wins are bug classes and API safety; measure both. |
| "Two kernels double the work." | Yes. Limited to a tiny spec and to M6, then one is frozen. |
| "Is the enclave controller even needed?" | The PL cores can run behind a hardware state machine. The controller is justified only if it makes rate limits, key custody and sequencing simpler or safer. Decide at E0. |
| "VexRiscv is missing today." | Correct: E0 is the first milestone. The earlier "SoC verified" status in `PROGRESS.md` is not supported by the files. |
| "Is a typed job API novel?" | Probably not as an idea (ownership-based DMA exists in Rust embedded crates). The claim, if any, is the measured fit for this enclave. Run a prior-art check first. |
| "Is it secure?" | An RTOS does not make a system secure. Security comes from small exposed surface, reviewed libraries, fuzzing, and hardware key isolation. |
| "Will it beat RT-Thread in a niche?" | RT-Thread is mature and broad. We aim to beat it only where its design has no answer (section 3), and only if measured. |

## 9. Risks

- E0 (a real soft-core) may take longer than the kernel work. Time-box it and fall back to a
  simulator-only plan if the board build stalls.
- Rust on RV32IM without atomics or the compressed set may need nightly features or extra crates.
- Linux-to-enclave mailbox timing and DDR sharing add integration risk at M4.
- Scope creep: no network stack or file system in the kernel.
