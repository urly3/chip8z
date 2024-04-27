const std = @import("std");
const CPU = struct {
    // 16 8bit registers - 0x00 thorugh 0x0f.
    // index into them to get values.
    var registers: [16]u8 = .{0} ** 10;
    var memory: [4096]u8 = undefined;
};

fn readInstruction(cpu: *CPU) void {
    const cur: [*]u8 = cpu.memory.ptr;

    if (cur & 0x00 < 0x10) {
        switch (cur[1]) {
            // clear.
            0xe0 => return,
            // return from sr.
            0xee => return,
            // execute sr.
            else => return,
        }

        return;
    }

    if (cur & 0x1000 == 0x1000) {
        // jump to addr.
        return;
    }

    if (cur & 0x2000 == 0x3000) {
        // execute sr.
        return;
    }
    if (cur & 0x3000 == 0x3000) {
        // skip next if rx == nn.
        return;
    }
    if (cur & 0x4000 == 0x4000) {
        // skip next if rx != nn.
        return;
    }
    if (cur & 0x5000 == 0x5000) {
        // skip next if rx == ry.
        return;
    }
    if (cur & 0x6000 == 0x6000) {
        // store nn in rx;
        return;
    }
    if (cur & 0x7000 == 0x7000) {
        // add nn to rx.
        return;
    }
    if (cur & 0x8000 == 0x8000) {
        // store ry in rx.

        // set rx to rx | ry.

        // set rx to rx & ry.

        // set rx to rx ^ ry.

        // add ry to rx,
        // set rf to carry.

        // sub ry from rx,
        // set rf to !borrow.

        // store ry >> in rx,
        // set rf to ry to lsb pre-shift.

        // store ry - rx in rx,
        // set rf to !borrow.

        // store ry << in rx,
        // set rf to msb pre-shift.
        return;
    }
    if (cur & 0x9000 == 0x9000) {
        // skip next if rx != ry.
        return;
    }
    if (cur & 0xa000 == 0xa000) {
        return;
    }
    if (cur & 0xb000 == 0xb000) {
        return;
    }
    if (cur & 0xc000 == 0xc000) {
        return;
    }
    if (cur & 0xd000 == 0xd000) {
        return;
    }
    if (cur & 0xe000 == 0xe000) {
        return;
    }
    if (cur & 0xf000 == 0xf000) {
        return;
    }
}

fn unimplementedInstruction(code: u8, code2: u8) void {
    std.log.err("instruction not implemented: {x:0>2}{x:0>2}", .{ code, code2 });
    @panic("^- unimpl");
}
