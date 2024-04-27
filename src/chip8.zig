const std = @import("std");
const CPU = struct {
    a: u8 = 0,
    b: u8 = 0,
    c: u8 = 0,
    d: u8 = 0,
    e: u8 = 0,
    f: u8 = 0,
    g: u8 = 0,
    h: u8 = 0,
    i: u8 = 0,
    j: u8 = 0,
    k: u8 = 0,
    l: u8 = 0,
    m: u8 = 0,
    n: u8 = 0,
    o: u8 = 0,
    p: u8 = 0,
    memory: []u8,
};

fn readInstruction(cpu: *CPU) void {
    const cur: [*]u8 = cpu.memory.ptr;

    if (cur == 0) {
        switch (cur[1]) {
            0xe0 => return,
            0xee => return,
            else => return,
        }

        return;
    }
}

fn unimplementedInstruction(code: u8, code2: u8) void {
    std.log.err("instruction not implemented: {x:0>2}{x:0>2}", .{ code, code2 });
    @panic("^- unimpl");
}
