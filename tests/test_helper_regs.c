#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

#include "dispatch.h"
#include "mmu.h"
#include "translate.h"

HvHelperInfo helper_test_info;
static uint32_t leave_block;
extern void helper_test_block(void), hv_exit(void);

uint32_t hv_helper(HvCpu *cpu, const HvHelperInfo *info) {
    (void)cpu;
    assert(info == &helper_test_info);
    __asm__ volatile("movi v4.16b, #0; movi v7.16b, #0; movi v16.16b, #0; movi v31.16b, #0"
                     ::: "v4", "v7", "v16", "v31");
    return leave_block;
}

int hv_tlb_refill(HvCpu *cpu, uint64_t va, uint32_t flags) {
    (void)cpu, (void)va, (void)flags;
    abort();
}

void *hv_ijc_resolve(HvCpu *cpu, uint64_t va, uint32_t flags) {
    (void)cpu, (void)va, (void)flags;
    abort();
}

int main(void) {
    static HvCpu cpu;
    int checks = 0;
    for (leave_block = 0; leave_block <= 1; leave_block++) {
        for (uint32_t op = HV_OP_MEM; op <= HV_OP_WFE; op++) {
            helper_test_info.op = op;
            cpu.exit_routine = (uint64_t)(uintptr_t)hv_exit;
            for (int i = 0; i < 32; i++) cpu.v[i] = (__uint128_t)(i + 1) << 64 | (uint64_t)(i + 33);
            hv_enter(&cpu, (void *)helper_test_block);
            for (int i = 0; i < 32; i++) {
                assert(cpu.v[i] == ((__uint128_t)(i + 1) << 64 | (uint64_t)(i + 33)));
                checks++;
            }
        }
    }
    printf("helper registers: %d checks\n", checks);
    return 0;
}
