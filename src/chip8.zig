const std = @import("std");

const Chip8 = struct {
    var memory: [4096]u8 = undefined;
    var cpu: CPU = .{
        .memory = &memory[0],
        .cur = &memory[0x0200],
    };
};

const CPU = struct {
    // 16 8bit registers - 0x00 thorugh 0x0f.
    // index into them to get values.
    var registers: [16]u8 = .{0} ** 10;
    const memory: [*]u8 = undefined;
    var i: u16 = 0;
    var cur: [*]u8 = undefined;
};

fn readInstruction(cpu: *CPU) void {
    if (cpu.cur[0] & 0x00 == 0x00) {
        switch (cpu.cur[1]) {
            // clear the screen.
            0xe0 => return,
            // return from sr.
            0xee => return,
            else => unimplementedInstruction(cpu.cur[0], cpu.cur[1]),
        }

        return;
    }

    if (cpu.cur[0] & 0x1000 == 0x1000) {
        // jump to addr.
        const addr: u12 = std.mem.readInt(u12, cpu.cur + 1, .big);
        cpu.cur = &cpu.memory[addr];
        return;
    }

    if (cpu.cur[0] & 0x2000 == 0x3000) {
        // execute sr.
        return;
    }

    if (cpu.cur[0] & 0x3000 == 0x3000) {
        // skip next if rx == nn.
        const rx: u8 = cpu.cur[0] & 0x0f;
        if (cpu.registers[rx] == cpu.cur[1]) {
            cpu.cur += 4;
        } else {
            cpu.cur += 2;
        }

        return;
    }

    if (cpu.cur[0] & 0x4000 == 0x4000) {
        // skip next if rx != nn.
        const rx: u8 = cpu.cur[0] & 0x0f;
        if (cpu.registers[rx] != cpu.cur[1]) {
            cpu.cur += 4;
        } else {
            cpu.cur += 2;
        }

        return;
    }

    if (cpu.cur[0] & 0x5000 == 0x5000) {
        // skip next if rx == ry.
        const rx: u8 = cpu.cur[0] & 0x0f;
        const ry: u8 = cpu.cur[1] >> 1;

        if (cpu.registers[rx] == cpu.registers[ry]) {
            cpu.cur += 4;
        } else {
            cpu.cur += 2;
        }

        return;
    }

    if (cpu.cur[0] & 0x6000 == 0x6000) {
        // store nn in rx;
        const rx: u8 = cpu.cur[0] & 0x0f;
        cpu.registers[rx] = cpu.cur[1];
        cpu.cur += 2;

        return;
    }

    if (cpu.cur[0] & 0x7000 == 0x7000) {
        // add nn to rx.
        const rx: u8 = cpu.cur[0] & 0x0f;
        cpu.registers[rx] += cpu.cur[1];
        cpu.cur += 2;
        return;
    }

    if (cpu.cur[0] & 0x8000 == 0x8000) {
        switch (cpu.cur[1] & 0x0f) {
            // store ry in rx.
            0x00 => {
                const rx: u8 = cpu.cur[0] & 0x0f;
                const ry: u8 = cpu.cur[1] >> 1;
                cpu.registers[rx] = cpu.registers[ry];
                cpu.cur += 2;
                return;
            },
            // set rx to rx | ry.
            0x01 => {
                const rx: u8 = cpu.cur[0] & 0x0f;
                const ry: u8 = cpu.cur[1] >> 1;
                cpu.registers[rx] |= cpu.registers[ry];
                cpu.cur += 2;
                return;
            },
            // set rx to rx & ry.
            0x02 => {
                const rx: u8 = cpu.cur[0] & 0x0f;
                const ry: u8 = cpu.cur[1] >> 1;
                cpu.registers[rx] &= cpu.registers[ry];
                cpu.cur += 2;
                return;
            },
            // set rx to rx ^ ry.
            0x03 => {
                const rx: u8 = cpu.cur[0] & 0x0f;
                const ry: u8 = cpu.cur[1] >> 1;
                cpu.registers[rx] ^= cpu.registers[ry];
                cpu.cur += 2;
                return;
            },
            // add ry to rx,
            // set rf to carry.
            0x04 => {
                const rx: u8 = cpu.cur[0] & 0x0f;
                const ry: u8 = cpu.cur[1] >> 1;
                const tmp: u8 = cpu.registers[ry];
                cpu.registers[rx] += tmp;

                cpu.registers[0x0f] = @intFromBool(cpu.registers[rx] < tmp);

                cpu.cur += 2;
                return;
            },
            // sub ry from rx,
            // set rf to !borrow.
            0x05 => {
                const rx: u8 = cpu.cur[0] & 0x0f;
                const ry: u8 = cpu.cur[1] >> 1;
                const tmp: u8 = cpu.registers[ry];
                cpu.registers[rx] -= tmp;

                cpu.registers[0x0f] = @intFromBool(!(cpu.registers[rx] > tmp));

                cpu.cur += 2;
                return;
            },
            // store ry >> 1 in rx,
            // set rf to ry lsb pre-shift.
            0x06 => {
                const rx: u8 = cpu.cur[0] & 0x0f;
                const ry: u8 = cpu.cur[1] >> 1;
                const lsb: u8 = (cpu.registers[ry] & 0x01);

                cpu.registers[rx] = cpu.registers[ry] >> 1;
                cpu.registers[0x0f] = lsb;

                cpu.cur += 2;
                return;
            },
            // store ry - rx in rx,
            // set rf to !borrow.
            0x07 => {
                const rx: u8 = cpu.cur[0] & 0x0f;
                const ry: u8 = cpu.cur[1] >> 1;
                const tmp: u8 = cpu.registers[rx];
                cpu.registers[rx] = cpu.registers[ry] - tmp;

                cpu.registers[0x0f] = @intFromBool(!(cpu.registers[rx] > tmp));

                cpu.cur += 2;
                return;
            },
            // store ry << in rx,
            // set rf to msb pre-shift.
            0x08 => {
                const rx: u8 = cpu.cur[0] & 0x0f;
                const ry: u8 = cpu.cur[1] >> 1;
                const msb: u8 = (cpu.registers[ry] & 0x80);

                cpu.registers[rx] = cpu.registers[ry] << 1;
                cpu.registers[0x0f] = msb;

                cpu.cur += 2;
                return;
            },
            else => unimplementedInstruction(cpu.cur[0], cpu.cur[1]),
        }
    }

    if (cpu.cur[0] & 0x9000 == 0x9000) {
        // skip next if rx != ry.
        const rx: u8 = cpu.cur[0] & 0x0f;
        const ry: u8 = cpu.cur[1] >> 1;

        if (cpu.registers[rx] != cpu.registers[ry]) {
            cpu.cur += 4;
        } else {
            cpu.cur += 2;
        }

        return;
    }

    if (cpu.cur[0] & 0xa000 == 0xa000) {
        // i == nnn.
        const addr: u12 = cpu.cur[0] & 0x0f;
        addr <<= 8;
        addr |= cpu.cur[1];
        cpu.i = addr;

        cpu.cur += 2;

        return;
    }

    if (cpu.cur[0] & 0xb000 == 0xb000) {
        // i == nnn + r0.
        const addr: u12 = cpu.cur[0] & 0x0f;
        addr <<= 8;
        addr |= cpu.cur[1];
        addr += cpu.registers[0x00];
        cpu.i = addr;

        cpu.cur += 2;

        return;
    }

    if (cpu.cur[0] & 0xc000 == 0xc000) {
        // rx = random number 0-255 & NN.
        const rx: u8 = cpu.cur[0] & 0x0f;
        //TODO: RANDOM NUMBER
        const random: u8 = 66;
        cpu.registers[rx] = random & cpu.cur[1];

        cpu.cur += 2;
        return;
    }

    if (cpu.cur[0] & 0xd000 == 0xd000) {
        // draw sprite at rx, ry with Nbytes of data,
        // starting at i,
        // rf = 1 if pixel unset, else 0.

        cpu.cur += 2;
        return;
    }

    if (cpu.cur[0] & 0xe000 == 0xe000) {
        switch (cpu.cur[1]) {
            // skip next if key pressed in rx.
            0x9e => {
                return;
            },
            // skip next if key pressed not in rx.
            0xa1 => {
                return;
            },
            else => unimplementedInstruction(cpu.cur[0], cpu.cur[1]),
        }
    }

    if (cpu.cur[0] & 0xf000 == 0xf000) {
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
        return;
    }
}

fn unimplementedInstruction(code: u8, code2: u8) void {
    std.log.err("instruction not implemented: {x:0>2}{x:0>2}", .{ code, code2 });
    @panic("^- unimpl");
}
