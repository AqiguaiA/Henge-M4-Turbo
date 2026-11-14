    .text
    .p2align 2
    .globl _helper_test_block
_helper_test_block:
    stp x0, x1, [x28]
    str x30, [x28, #240]
    adrp x0, _helper_test_info@PAGE
    add x0, x0, _helper_test_info@PAGEOFF
    bl _hv_helper_entry
    b _hv_exit
