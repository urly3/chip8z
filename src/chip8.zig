const std = @import("std");

pub const Chip8 = struct {
    memory: []u8,
    stack: [*]u8,
    display: []u8,
    cpu: CPU = .{},
};

pub const CPU = struct {
    // 16 8bit registers - 0x00 thorugh 0x0f.
    registers: [16]u8 = .{0} ** 16,
    // a pointer set to the start of the interps memory addr.
    memory: [*]u8 = undefined,
    // display buffer.
    display: [*]u8 = undefined,
    // memory addr storage (12bit).
    i: u16 = 0,
    // current location in memory.
    pc: [*]u8 = undefined,
};

pub fn readInstruction(cpu: *CPU) void {
    // std.debug.print("cur: {x:0>2} {x:0>2}\n", .{ cpu.pc[0], cpu.pc[1] });
    const rx: u8 = cpu.pc[0] & 0x0f;
    const ry: u8 = cpu.pc[1] >> 4;
    var go_next: bool = true;
    defer {
        if (go_next) cpu.pc += 2;
    }

    if (cpu.pc[0] == 0x00) {
        //     std.debug.print("0x00", .{});
        switch (cpu.pc[1]) {
            // clear the screen.
            0xe0 => {
                for (cpu.display[0 .. 64 * 32]) |*pix| {
                    pix = 0;
                }
            },
            // return from sr.
            0xee => unimplementedInstruction(cpu.pc[0], cpu.pc[1]),
            else => unimplementedInstruction(cpu.pc[0], cpu.pc[1]),
        }

        return;
    }

    if (cpu.pc[0] & 0xf0 == 0x10) {
        // jump to addr.
        //     std.debug.print("0x10", .{});
        const addr: u16 = std.mem.readInt(u16, cpu.pc[0..2], .big) & 0x0fff;
        cpu.pc = cpu.memory[addr..];
        go_next = false;
        //     std.debug.print("addr: {x:0>4}", .{addr});
        return;
    }

    if (cpu.pc[0] & 0xf0 == 0x20) {
        //     std.debug.print("0x20", .{});
        // execute sr.
        return;
    }

    if (cpu.pc[0] & 0xf0 == 0x30) {
        //     std.debug.print("0x30", .{});
        // skip next if rx == nn.
        if (cpu.registers[rx] == cpu.pc[1]) {
            cpu.pc += 2;
        }

        return;
    }

    if (cpu.pc[0] & 0xf0 == 0x40) {
        //     std.debug.print("0x40", .{});
        // skip next if rx != nn.
        if (cpu.registers[rx] != cpu.pc[1]) {
            cpu.pc += 2;
        }

        return;
    }

    if (cpu.pc[0] & 0xf0 == 0x50) {
        //     std.debug.print("0x50", .{});
        // skip next if rx == ry.

        if (cpu.registers[rx] == cpu.registers[ry]) {
            cpu.pc += 2;
        }

        return;
    }

    if (cpu.pc[0] & 0xf0 == 0x60) {
        //     std.debug.print("0x60", .{});
        // store nn in rx;
        cpu.registers[rx] = cpu.pc[1];

        return;
    }

    if (cpu.pc[0] & 0xf0 == 0x70) {
        //     std.debug.print("0x70", .{});
        // add nn to rx.
        cpu.registers[rx] += cpu.pc[1];
        return;
    }

    if (cpu.pc[0] & 0xf0 == 0x80) {
        //     std.debug.print("0x80", .{});
        switch (cpu.pc[1] & 0x0f) {
            // store ry in rx.
            0x00 => {
                cpu.registers[rx] = cpu.registers[ry];
                return;
            },
            // set rx to rx | ry.
            0x01 => {
                cpu.registers[rx] |= cpu.registers[ry];
                return;
            },
            // set rx to rx & ry.
            0x02 => {
                cpu.registers[rx] &= cpu.registers[ry];
                return;
            },
            // set rx to rx ^ ry.
            0x03 => {
                cpu.registers[rx] ^= cpu.registers[ry];
                return;
            },
            // add ry to rx,
            // set rf to carry.
            0x04 => {
                const tmp: u8 = cpu.registers[ry];
                cpu.registers[rx] += tmp;

                cpu.registers[0x0f] = @intFromBool(cpu.registers[rx] < tmp);

                return;
            },
            // sub ry from rx,
            // set rf to !borrow.
            0x05 => {
                const tmp: u8 = cpu.registers[ry];
                cpu.registers[rx] -= tmp;

                cpu.registers[0x0f] = @intFromBool(!(cpu.registers[rx] > tmp));

                return;
            },
            // store ry >> 1 in rx,
            // set rf to ry lsb pre-shift.
            0x06 => {
                const lsb: u8 = (cpu.registers[ry] & 0x01);

                cpu.registers[rx] = cpu.registers[ry] >> 1;
                cpu.registers[0x0f] = lsb;

                return;
            },
            // store ry - rx in rx,
            // set rf to !borrow.
            0x07 => {
                const tmp: u8 = cpu.registers[rx];
                cpu.registers[rx] = cpu.registers[ry] - tmp;

                cpu.registers[0x0f] = @intFromBool(!(cpu.registers[rx] > tmp));

                return;
            },
            // store ry << in rx,
            // set rf to msb pre-shift.
            0x08 => {
                //             std.debug.print("shift left.\n", .{});
                const msb: u8 = (cpu.registers[ry] & 0x80);

                cpu.registers[rx] = cpu.registers[ry] << 1;
                cpu.registers[0x0f] = msb;

                return;
            },
            else => unimplementedInstruction(cpu.pc[0], cpu.pc[1]),
        }
    }

    if (cpu.pc[0] & 0xf0 == 0x90) {
        //     std.debug.print("0x90", .{});
        // skip next if rx != ry.

        if (cpu.registers[rx] != cpu.registers[ry]) {
            cpu.pc += 2;
        }
        return;
    }

    if (cpu.pc[0] & 0xf0 == 0xa0) {
        //     std.debug.print("0xa0", .{});
        // i == nnn.
        var addr: u16 = cpu.pc[0] & 0x0f;
        addr <<= 8;
        addr |= cpu.pc[1];
        cpu.i = addr;

        return;
    }

    if (cpu.pc[0] & 0xf0 == 0xb0) {
        //     std.debug.print("0xb0", .{});
        // i == nnn + r0.
        var addr: u12 = cpu.pc[0] & 0x0f;
        addr <<= 8;
        addr |= cpu.pc[1];
        addr += cpu.registers[0x00];
        cpu.i = addr;

        return;
    }

    if (cpu.pc[0] & 0xf0 == 0xc0) {
        //     std.debug.print("0xc0", .{});
        // rx = random number 0-255 & NN.
        //TODO: RANDOM NUMBER
        const random: u8 = 66;
        cpu.registers[rx] = random & cpu.pc[1];

        return;
    }

    if (cpu.pc[0] & 0xf0 == 0xd0) {
        //     std.debug.print("0xd0", .{});
        // draw sprite at rx, ry with Nbytes of data,
        // starting at i,
        // rf = 1 if pixel unset, else 0.

        const n: u8 = cpu.pc[1] & 0x0f;

        const x = cpu.registers[rx] % 64;
        const y = cpu.registers[ry] % 32;
        var idx: usize = 0;
        var byte: u8 = undefined;
        cpu.registers[0x0f] = 0;
        while (idx < n) : (idx += 1) {
            byte = cpu.memory[cpu.i + idx];
            const coord = ((y + idx) * 64) + x;

            cpu.registers[0x0f] = cpu.display[coord] ^ (byte >> 7) & 0x01;
            cpu.display[coord] = cpu.registers[0x0f];

            cpu.registers[0x0f] = cpu.display[coord + 1] ^ (byte >> 6) & 0x01;
            cpu.display[coord + 1] = cpu.registers[0x0f];

            cpu.registers[0x0f] = cpu.display[coord + 2] ^ (byte >> 5) & 0x01;
            cpu.display[coord + 2] = cpu.registers[0x0f];

            cpu.registers[0x0f] = cpu.display[coord + 3] ^ (byte >> 4) & 0x01;
            cpu.display[coord + 3] = cpu.registers[0x0f];

            cpu.registers[0x0f] = cpu.display[coord + 4] ^ (byte >> 3) & 0x01;
            cpu.display[coord + 4] = cpu.registers[0x0f];

            cpu.registers[0x0f] = cpu.display[coord + 5] ^ (byte >> 2) & 0x01;
            cpu.display[coord + 5] = cpu.registers[0x0f];

            cpu.registers[0x0f] = cpu.display[coord + 6] ^ (byte >> 1) & 0x01;
            cpu.display[coord + 6] = cpu.registers[0x0f];

            cpu.registers[0x0f] = cpu.display[coord + 7] ^ (byte) & 0x01;
            cpu.display[coord + 7] = cpu.registers[0x0f];
        }

        return;
    }

    if (cpu.pc[0] & 0xf0 == 0xe0) {
        //     std.debug.print("0xe0", .{});
        switch (cpu.pc[1]) {
            // skip next if key pressed in rx.
            0x9e => {
                unimplementedInstruction(cpu.pc[0], cpu.pc[1]);
            },
            // skip next if key pressed not in rx.
            0xa1 => {
                unimplementedInstruction(cpu.pc[0], cpu.pc[1]);
            },
            else => unimplementedInstruction(cpu.pc[0], cpu.pc[1]),
        }
    }

    if (cpu.pc[0] & 0xf0 == 0xf0) {
        //     std.debug.print("0xf0", .{});
        // store delay timer in rx.

        // wait key press, store in rx.

        // set delay timer to rx.

        // set sound time to rx.

        // add rx to i.

        // set i to rx sprite data addr.

        // store bcd of rx at i, i + 1, i + 2.

        // store r0 through rx (incl) starting at i,
        // i = i + x + 1.

        // fill r0 to rx (incl) with values starting at addr i.
        // i = i + x + 1.
        unimplementedInstruction(cpu.pc[0], cpu.pc[1]);
        return;
    }

    unimplementedInstruction(cpu.pc[0], cpu.pc[1]);
}

fn unimplementedInstruction(code: u8, code2: u8) void {
    std.log.err("instruction not implemented: {x:0>2}{x:0>2}", .{ code, code2 });
    @panic("^- unimpl");
}
