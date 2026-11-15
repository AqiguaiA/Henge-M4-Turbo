<p align="center">
  <img src="docs/icon.png" width="120" height="120" alt="Henge">
</p>

<h1 align="center">Henge M4-Turbo</h1>

<p align="center">macOS on your iPhone and iPad — tuned with <code>-O3 -mcpu=apple-m4</code> &amp; JIT/MMU/I/O optimizations for M4 iPad Pro (iPadOS 27.2).</p>

<p align="center">
  <a href="#m4-turbo-optimizations--fixes-apple-m4-ipad-pro--ipados-272">M4-Turbo Optimizations</a>
  ·
  <a href="#install">Install</a>
  ·
  <a href="docs/architecture.md">How it works</a>
  ·
  <a href="https://github.com/AqiguaiA/Henge-M4-Turbo/actions">Actions Builds</a>
  ·
  <a href="https://github.com/Leviidev/Henge">Upstream</a>
</p>

<p align="center">
  <a href="https://github.com/Leviidev/Henge/releases"><img src="https://img.shields.io/github/downloads/Leviidev/Henge/total?style=flat-square&color=2E6BFF&labelColor=111111" alt="Downloads"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Leviidev/Henge?style=flat-square&color=2E6BFF&labelColor=111111" alt="GPL-2.0-or-later"></a>
</p>

## M4-Turbo Optimizations & Fixes (Apple M4 iPad Pro / iPadOS 27.2)

> **GPL-2.0-or-later 开源合规与修改声明 (Modification & License Notice)**
>
> - 本仓库（`AqiguaiA/Henge-M4-Turbo`）为基于上游 [Leviidev/Henge](https://github.com/Leviidev/Henge)（Copyright © Leviidev and contributors）的**非官方衍生修改版**，并非原作者原始发布版本。
> - 依据 **GNU General Public License v2.0 (GPLv2) 第 2(a) 条**：本衍生分支在 **`2026-11-14` 至 `2026-11-15`** 期间对核心转译与运行期模块进行了修改与增补，涵盖目录与文件：`core/`、`host/`、`devices/`、`ios/`、`tests/`、`Makefile`、[`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml) 与 `README.md`。
> - 依据 **GPLv2 第 2(b) 条与第 11–12 条**：本衍生作品整体及全部修改内容继续以 **`GPL-2.0-or-later`** 协议免费向所有第三方开源发布（详见 [LICENSE](LICENSE) 与 [docs/licensing.md](docs/licensing.md)），并**按“现状”分发、不提供任何明示或默示担保（AS IS, WITHOUT ANY WARRANTY）**。

本仓库基于 [Leviidev/Henge](https://github.com/Leviidev/Henge) 构建，面向 **非越狱 Apple M4 iPad Pro（iPadOS 27.2）** 进行针对性引擎性能优化、稳定性格外审计修复、免费签名打包适配与妙控板手势增强：

### 1. M4-Turbo 引擎与图形栈核心优化（Fork Enhancements）
1. **Apple M4 全栈优化编译与性能核调度**：iOS 引擎静态库采用 `-O3 -mcpu=apple-m4` 编译（[`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml)），`host/vm.c` 与 `devices/pvg_metal.m` 将 guest vCPU 及 Metal 回放队列调度至 `QOS_CLASS_USER_INTERACTIVE`，优先锁定 M4 P-Core。
2. **默认高性能转译参数与超块扩容**：默认开启 `HV_SUPERBLOCKS=1`、`HV_WFI_SPIN=50`、`HV_FLUSH=2`（`F_BARRIERFSYNC`）、`HV_HZ=60`、`HV_STATS=0`，并默认 `HV_RECHECK=0`；`go_on()`（[`core/translate.c`](core/translate.c)）将超块（Superblock）单块上限由 `48` 提升至 **`96`** 条指令，扩大跨条件分支直线/热路径编译窗口。
3. **`CLREX` 零陷出内联发射**：`core/translate.c` 对 `HV_INSN_BARRIER` (`CLREX`) 直接内联写入 `cpu->excl_addr`（`movn x6, #0` + `str x6, [x28, #HV_CPU_EXCL_ADDR]`），避免每次 `CLREX` 陷入 `hv_helper`。
4. **零 Spill PAC 指针剥离（`put_strip()`）**：`core/translate.c` 在运行期按地址 `bit 55` 符号扩展 `bits 54..48`，非 stolen 寄存器仅通过宿主机暂存寄存器 `x6` 发射 2 条指令完成剥离，零寄存器 Spill 且同时兼容 EL0/EL1 地址空间。
5. **64/128-bit 独占对访存快路径与 `translate_excl()` 统一收口**：`core/translate.c` 将单字（`LDXR`/`STXR` 等）与成对（`LDXP`/`STXP` 等）独占访存统一至 `translate_excl()`，在 TLB 命中与对齐校验通过后，仅用宿主机空闲暂存寄存器 `x6`/`x7`/`x15` 执行 `LDP` 与原生 `CASAL`/`CASPAL`；结合原有 `HV_IJC_BITS=18` 间接跳转缓存（`cpu->ijc_tab[]`）与零陷入系统寄存器快路径（`TPIDR_EL0`/`TPIDRRO_EL0`/`NZCV`/`CNTVCT_EL0` 等），显著降低原子锁与上下文热点开销。
6. **软件 MMU 内核范围快扫与 `PVGMetal` 直达对象缓存**：
   - `core/mmu.c` 的 `hv_tlb_flush_kernel_range()` 将逐页扫描阈值调为 256 页（4 MB），超出时若 `cpu->nkernel_fills <= HV_KERNEL_FILLS` 则仅扫描已填充索引 `cpu->kernel_fills[]`，避免全表扫描；
   - `devices/pvg_metal.m` 的 `HvReplay` 新增 4096 槽位 C 级哈希缓存 `obj_cache[]`（`HV_OBJ_CACHE_SIZE = 4096`），绕过 `NSNumber` 装箱与双层 `NSMutableDictionary` 查找热路径。

### 2. 关键正确性与稳定性修复（Round 1 & Round 2 Audit Fixes）
- **独占访存监视器与异常注入统一修复**：`translate_excl()` 先完成对齐与 TLB 权限校验再更新目标寄存器及独占监视器（`excl_addr` 与 `excl_size`），完整处理 `XZR` 与 stolen 寄存器冲突；`core/memop.c` 的 `do_exclusive()` 在物理写失败时按架构语义注入 `HV_FSC_EXTERNAL` Data Abort，不再静默吞掉总线错误。
- **Helper 全量浮点与条件码上下文保护**：[`host/enter.S`](host/enter.S) 中 `_hv_helper_entry` 在进入 `hv_helper` 前后使用 `SAVE_FLAGS_FP` / `LOAD_FLAGS_FP` 完整保存与恢复 Guest 的全部 `q0..q31` SIMD/FP 寄存器及 `NZCV` 条件码，配合 [`Makefile`](Makefile) 中 `mmu.o` 与 `exception.o` 的 `-mgeneral-regs-only` 编译约束，彻底避免 `-O3 -mcpu=apple-m4` 自动向量化破坏 Guest 状态（已新增 `test_helper_regs` 验证）。
- **内核高端虚拟地址 64 位回绕修复**：修正 `core/mmu.c` 与 `core/sysreg.c` 中当内核 VA 区间终点位于 `0xffffffffffffffff` 时进行 `+ 1` 计算导致的 64 位无符号整数溢出回绕缺陷（`test_mmu` 新增覆盖测试）。
- **`EngineTuning` 环境变量生命周期修正**：[`ios/Henge/EngineTuning.swift`](ios/Henge/EngineTuning.swift) 关闭开关时显式写入 `HV_SUPERBLOCKS=0`（避免被默认启用覆盖），并追踪 `appliedKeys` 以便在重新应用 `Documents/henge-env.txt` 时自动 `unsetenv` 已删除的键值（已新增 `test_engine_tuning` 验证）。
- **iPadOS 27.2 (TXM) 免费个人签名与 JIT 引导适配**：CI 默认使用 [`ios/Henge/Henge.personal.entitlements`](ios/Henge/Henge.personal.entitlements)（仅保留 `get-task-allow` 与 `com.apple.developer.kernel.increased-memory-limit`），避免免费 Apple ID 安装出现 `-80045` 并满足 iPadOS 27.2 TXM 校验，配合 StikDebug / StikJIT 引导启用设备端 JIT。

### 3. Round 3 优化（6 GB+ 客户机内存解锁与系统寄存器 / `IC IALLU` 零陷出内联）
1. **释放 60 GB 高位虚拟地址保留，解锁 6 GB–8 GB 客户机内存**（[`ios/Henge/Native/henge-ios-jit.c`](ios/Henge/Native/henge-ios-jit.c)、[`ios/Henge/Native/henge-ios-jit.h`](ios/Henge/Native/henge-ios-jit.h)、[`ios/Henge/Native/henge-vm.c`](ios/Henge/Native/henge-vm.c)）：
   - 原 `henge_ios_jit_prewarm()` 会通过 `henge_ios_hold_high()` 预留 `60 GB`（`40 GB + 16 GB + 4 GB`）高端 VA 给实验性 Mac App 运行时，而启动 `hengevm` 虚拟机时未调用 `henge_ios_release_high_hold()` 归还，导致 `henge_largest_mapping_mb()` 仅探测到约 `2.5 GB` 连续虚拟地址空间并将用户设置的 6 GB RAM 静默压缩至 `2048 MB`。
   - 现于 `henge_largest_mapping_mb()` 探测前及 `henge_ios_jit_get_mapping()` 中显式调用 `henge_ios_release_high_hold()` 归还这 60 GB 高位保留（非 iOS 测试桩同步补齐空实现），开启 `extended-virtual-addressing` 时可完整解锁 6 GB–8 GB 内存分配；[`ios/Henge/Machines.swift`](ios/Henge/Machines.swift) 的 `GuestMemory.prepare()` 同步将低 VA 场景预留裕量由固定 `512 MB` 优化为动态 `256 MB` / `512 MB`（按 `256 MB` 对齐），并在 [`ios/Henge/SessionView.swift`](ios/Henge/SessionView.swift) 详情页新增实时 `Memory`（`bootRAM`）显示与低连续虚拟地址空间专属报错提示、前置 `henge_vm_can_start()` 检查。
2. **自适应 Code Cache 默认大小**（[`ios/Henge/JIT/JITBootstrap.swift`](ios/Henge/JIT/JITBootstrap.swift)）：`defaultCodeCacheMB` 在检测到缺少 `extended-virtual-addressing`（`henge_largest_reservation_gb() < 16`，例如免费个人证书侧载）时自动收敛为 **`512 MB`**（显著减少 JIT 双映射 Rx/Rw 区域及翻译块记录占用的低端虚拟地址空间），保留 `extended-virtual-addressing` 设备上的 `1536 MB` 默认上限。
3. **热路径系统寄存器与 EL1 `IC IALLU` / `IC IALLUIS` 零陷出内联**（[`core/cpu.h`](core/cpu.h)、[`core/translate.c`](core/translate.c)）：
   - 将 `ttbr0_el1`、`ttbr1_el1`、`vbar_el1`、`mair_el1`、`contextidr_el1`、`cpacr_el1`、`mdscr_el1`、`cntkctl_el1`、`mpidr` 9 个高频 EL1 字段紧密排布进 `helper_came_from`（`0x510`）与 `tlb`（`0x580`）之间原有的 104 字节对齐空隙中，保持 `HV_CPU_TLB`（`0x580`）与 `HV_CPU_RET_TAB`（`0x201000`）偏移完全不变并附带 `_Static_assert` 校验；
   - 在 `translate_sysreg_inline()` 中新增内联 `DCZID_EL0`，扩展 EL1 读写表 `el1_rw[]`（新增 `CONTEXTIDR_EL1`、`MDSCR_EL1` 并升级 `ESR_EL1`/`FAR_EL1`/`PAR_EL1` 写操作为直接内存存储），新增 EL1 只读表 `el1_ro[]`（内联 `TTBR0_EL1`、`TTBR1_EL1`、`VBAR_EL1`、`MAIR_EL1`、`CPACR_EL1`、`CNTKCTL_EL1`、`MPIDR_EL1` 读取），以及 EL1 常量表 `el1_const[]`（`CNTFRQ_EL0`、`CTR_EL0`、`MIDR_EL1`、`CLIDR_EL1` 与 `ID_AA64{PFR0,DFR0,ISAR0,ISAR1,MMFR0,MMFR1}_EL1`），共在 4 张分组内涵盖 28 个热系统寄存器访问，跳过 `_hv_helper_entry` 陷阱切换；
   - `translate_one()` 对 EL1 下的 `IC IALLU` / `IC IALLUIS` 在未显式设置 `HV_IC_FLUSH` 时直接按零陷出空操作处理，不触发 helper 调用或截断超块。
4. **Apple Magic Keyboard / 外接妙控板快捷手势与触控快捷菜单**（[`ios/Henge/Hardware.swift`](ios/Henge/Hardware.swift)、[`ios/Henge/Trackpad.swift`](ios/Henge/Trackpad.swift)、[`ios/Henge/SessionView.swift`](ios/Henge/SessionView.swift)）：
   - **键盘修饰键 + 妙控板手势合成（3 指/2 指）**：因 iPadOS 会截获物理妙控板原生 3/4 指系统手势，现支持在使用物理妙控板时按住 **`⌃ Control` + 双指滑动** 自动合成 USB Magic Trackpad 2 原生 **3 指滑动**（上滑打开 **调度中心 Mission Control**、下滑 **应用程序窗口 App Exposé**、左右滑动切换 **空间 Spaces**）；按住 **`⌥ Option` + 双指滑动** 合成 **2 指连续触控板滑动**（Safari/Finder 前进后退与平滑平移）；
   - **双指捏合 / 旋转与快捷切换**：物理妙控板上的直接**双指捏合缩放**与**双指旋转**会合成至虚拟 USB Magic Trackpad 2；按住 **`⌃ Control` 或 `⌥ Option` 双指捏合/张开** 可触发 **启动台（Launchpad）** 与 **显示桌面（Show Desktop）**；
   - **会话工具栏手势菜单与平滑滚动控制**：在 [`SessionView.swift`](ios/Henge/SessionView.swift) 竖屏与横屏/全屏工具栏新增手势菜单按钮（`rectangle.3.group`），可一键触发调度中心、App Exposé、左/右切换空间、显示桌面、启动台及 Spotlight（`⌘Space`）；物理妙控板/鼠标滚轮移除 `sqrt` 小值放大，改为亚刻度浮点余数累积、`30 ms` 节流包发送并支持最低 `0.05×` 滚动速度，避免触发 macOS 高速飞轮倍增。

### 4. GitHub Actions 自动构建与下载
每次推送至 `main` 分支或手动触发 [`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml) 时，将在 `xcode-27` macOS Runner 上自动执行以下流程：
1. 运行 Swift 测试 `make test-engine-tuning` 与 9 项核心 C/汇编单元测试（`test_classify`、`test_jit_region`、`test_operands`、`test_helper_regs`、`test_mmu`、`test_jit`、`test_mem`、`test_exc`、`test_shutdown`）。
2. 使用 `-O3 -mcpu=apple-m4` 编译 `libhengevm.a` 并通过 Xcode 27 + [`ios/scripts/package_ipa.sh`](ios/scripts/package_ipa.sh) 打包。
3. 在对应 [Actions Run](https://github.com/AqiguaiA/Henge-M4-Turbo/actions) 页面底部 **Artifacts** 中上传 `Henge-M4-Turbo-ipa-<sha>`（内含可直接侧载安装的 `Henge.ipa`）。

---

Download macOS, install it on the device, and use it.

- **Own emulator** — iOS gives apps no hypervisor, so Henge runs the Mac's arm64 code through its own JIT, with its own MMU and devices. It doesn't use QEMU or Virtualization.framework.
- **Installs on the device** — Henge downloads Apple's restore image and restores it the way a Mac does. No Mac needed, and nothing is decrypted or patched.
- **Graphics** — macOS draws through a virtual GPU, and Henge replays its commands with Metal. Safari and Electron apps like Discord draw on it.
- **Touch** — The screen is a Magic Trackpad 2: two fingers to scroll, and the Mac's own gestures work on it — three-finger swipes for Spaces and Mission Control and more. The volume buttons are its buttons: up clicks, down right-clicks, hold to drag. Esc, Tab, Control, Option and Command sit above the keyboard.
- **Keyboard and mouse** — On iPad, a Magic Keyboard or a Bluetooth keyboard and mouse drive the Mac directly.
- **External display** — During a Mac session, connect a display with a video-capable USB-C cable or a USB-C/HDMI dock. The mode activates automatically: the monitor shows the Mac, while the iPhone or iPad keeps its trackpad and keyboard controls. Disconnect to return the image to the device. The existing guest resolution is preserved. On iOS 17–26 the same happens through an older iOS route, not yet tried on hardware; outside a Mac session the display mirrors the device. USB-C video is user-confirmed on an iPhone 17 Pro running iOS 27 (development build 0.1/2).
- **Sharing** — Copy and paste between macOS and the device, and a shared folder that shows up in Files and on the Mac.
- **Fits the screen** — On iPad, a new Mac gets a screen the shape of the iPad's, so there are no black bars.

On an iPhone 17 Pro, macOS reaches the lock screen in about 15 seconds. Discord installs, opens in about 15 seconds, logs in and sends messages.

## Install

Sideload `Henge.ipa` from [Releases](https://github.com/Leviidev/Henge/releases) with SideStore or AltStore, or install `Henge.tipa` with TrollStore or TrollStore Lite. To get updates in SideStore or AltStore, add Henge's source, `https://raw.githubusercontent.com/Leviidev/Henge/main/repo.json`, or `https://itslevii.dev/repo.json` for all of Leviidev's apps. iOS or iPadOS 17 or later, on an A14 or M1 chip or newer. So far it's tested only on an iPhone 17 Pro: iPad support is new and hasn't run on a real iPad yet.

- **JIT** is required: StikDebug, TrollStore (which stops at iOS 17.0), TrollStore Lite (which needs a jailbreak), a jailbreak on its own, or the StikJIT helper built into Henge (iOS 26 or later).
- **Storage:** about 43 GB free for macOS Sequoia. That's 17 GB for the download, which you can delete afterwards, and 26 GB for the Mac.
- **Memory:** a Mac gets 4, 6 or 8 GB. Sign Henge with the increased memory limit entitlement if your certificate has it.

Then open the Install tab, pick macOS Sequoia 15.6.1, and keep Henge open with the device plugged in. Tahoe 26.6.2 and macOS 27.2 are offered too: both install and run on an iPhone 17 Pro, though Tahoe's first setup is slow and macOS 27 is the slowest (Safari's pages may stay blank on it). Sonoma 14.6.1 and Ventura 13.6 are smaller downloads (14.1 and 12.3 GB) for devices short on storage: they install, set up, and run Safari (both tested on an iPhone 17 Pro). Monterey isn't offered yet: it installs, but its desktop never appears.

## Sharing with the Mac

Do this once for each Mac: open Terminal on the Mac, then in Henge open Details and tap **Type the Set Up Command**. Press Return on the Mac, and choose Allow when macOS asks about `henge-agent` and local networks. It needs the Mac's keyboard layout to be U.S.

Then a Henge folder in the Mac's home folder is the same folder as Files › Henge › Shared. What you copy on the Mac is copied on the device too, and the paste button pastes from the device into the Mac.

## Known limits

- Signing in to an Apple Account inside macOS fails with a verification error.
- Graphics are tested on macOS's own apps, Chrome, Firefox, VS Code and Discord. Other apps may draw wrongly.
- On macOS Sonoma, switching to a dynamic wallpaper (such as Sonoma) can stop the screen updating; opening any app brings it back. On Ventura, the Calendar icon in the Dock is missing its date.
- For the first few minutes after you log in, macOS is busy starting up in the background, so apps open more slowly.
- Only one Mac can start per launch. Quit Henge and open it again to start another, and to start one again after restarting or shutting down macOS.
- iPadOS keeps some keyboard shortcuts for itself, such as Command-Tab.
- It's emulation, so it runs slower than a real Mac.

## Screenshots

<table>
  <tr>
    <td align="center" colspan="3"><img src="Screenshots/ipad.jpg" alt="Discord on an iPad"><br><sub>iPad</sub></td>
  </tr>
  <tr>
    <td align="center" width="33%"><img src="Screenshots/macs.png" alt="Macs"><br><sub>Macs</sub></td>
    <td align="center" width="33%"><img src="Screenshots/trackpad.png" alt="Trackpad"><br><sub>Trackpad</sub></td>
    <td align="center" width="33%"><img src="Screenshots/install.png" alt="Install macOS"><br><sub>Install macOS</sub></td>
  </tr>
</table>

<sub>Captured on a Mac: the app's own screens with sample data, at iPad and iPhone sizes, showing a frame from Henge's renderer.</sub>

## Building

To use Henge, install the [latest release](https://github.com/Leviidev/Henge/releases). Every change lands on `main` as it's made, so `main` can be unfinished between releases.

On a Mac with Xcode 27 or later and `xcodegen`. Henge takes StikJIT, on-device pairing, libslirp and glib from a built [Husk](https://github.com/Leviidev/Husk) checkout at `~/Documents/Coding/Husk` (set `HUSK` to use another path):

```bash
ios/scripts/fetch_deps.sh
tools/build_ios_restore.sh
make ios-lib
ios/scripts/package_ipa.sh
```

That produces `~/Desktop/Henge.ipa`, and `package_ipa.sh --trollstore` writes `Henge.tipa`.

`make` builds the engine for the Mac, `build/hengevm`, and `make test` runs its tests.

## Licence

GPL-2.0-or-later. Henge compiles in usbmuxd (GPLv2 or GPLv3) and code from Husk (GPL-2.0-or-later), so the shipped binary is a combined GPL work. It cannot go on the App Store. See [docs/licensing.md](docs/licensing.md).

macOS and the Mac's boot ROM are Apple's and aren't part of Henge. Henge downloads both from Apple when you install.
