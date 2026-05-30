const std = @import("std");

const debug = false;
const cli = true;

const screen_width = 64;
const screen_height = 32;

const cpu_hz = 480;

var random: std.Random = undefined;

const Snapshot = struct {
    pc: u16,
    opcode: u16,
    x: u4,
    y: u4,
    n: u4,
    nn: u8,
    nnn: u12,
    r: [16]u8,
    vx: u8,
    vy: u8,
    vf: u8,
    i: u12,

    fn create(chip8: *Chip8) Snapshot {
        const pc = chip8.program_counter;
        const opcode_bytes = chip8.memory[pc .. pc + 2];

        const opcode = std.mem.readVarInt(u16, opcode_bytes, .big);
        const x: u4 = @truncate(opcode >> 8);
        const y: u4 = @truncate(opcode >> 4);
        const n: u4 = @truncate(opcode);
        const nn: u8 = @truncate(opcode);
        const nnn: u12 = @truncate(opcode);

        const r = chip8.registers;
        const vx = r[x];
        const vy = r[y];
        const vf = r[0xf];

        const i = chip8.address_register;

        return .{
            .pc = pc,
            .opcode = opcode,
            .r = r,
            .vx = vx,
            .vy = vy,
            .vf = vf,
            .i = i,
            .x = x,
            .y = y,
            .n = n,
            .nn = nn,
            .nnn = nnn,
        };
    }
};

const Rom = struct {
    data: []const u8,

    fn load(allocator: std.mem.Allocator, io: std.Io, filename: []const u8) !Rom {
        var file = try std.Io.Dir.cwd().openFile(io, filename, .{});
        var reader = file.reader(io, &.{});
        return .{
            .data = try reader.interface.allocRemaining(allocator, .unlimited),
        };
    }

    fn unload(rom: *const Rom, allocator: std.mem.Allocator) void {
        allocator.free(rom.data);
    }
};

const Chip8 = struct {
    registers: [0x10]u8 = @splat(0),
    memory: [0x1000]u8 = @splat(0),
    address_stack: [0x30]u16 = @splat(0),
    delay_timer: u8 = 0,
    sound_timer: u8 = 0,

    address_register: u12 = 0,
    program_counter: u16 = 0x200,
    stack_index: u16 = 0,

    fn loadRom(chip8: *Chip8, rom: *const Rom) void {
        const end = 0x200 + rom.data.len;
        @memcpy(chip8.memory[0x200..end], rom.data);

        if (debug) {
            std.debug.print("rom loaded\n", .{});
            std.debug.print("{any}\n\n", .{chip8.memory});
        }
    }

    fn loadFont(chip8: *Chip8, font: []const u8) void {
        const end = 0x50 + font.len;
        @memcpy(chip8.memory[0x50..end], font);
        if (debug) {
            std.debug.print("font loaded\n", .{});
            std.debug.print("{any}\n\n", .{chip8.memory});
        }
    }

    // step through the next instruction in memory
    // at offset held in program_counter
    fn step(chip8: *Chip8) void {
        const memory: []u8 = &chip8.memory;
        const display: []u8 = memory[0xf00..];

        const pc = &chip8.program_counter;

        const opcode_bytes = chip8.memory[pc.* .. pc.* + 2];
        const opcode = std.mem.readVarInt(u16, opcode_bytes, .big);

        const x: u4 = @truncate(opcode >> 8);
        const y: u4 = @truncate(opcode >> 4);
        const n: u4 = @truncate(opcode);
        const nn: u8 = @truncate(opcode);
        const nnn: u12 = @truncate(opcode);

        const vx = &chip8.registers[x];
        const vy = &chip8.registers[y];
        const vf = &chip8.registers[0xf];

        const i = &chip8.address_register;

        if (debug) {
            std.debug.print("display starts at address: {p}\n", .{&display[0]});

            std.debug.print("pc: {x}\n", .{pc.*});

            std.debug.print("op uint: {x}\n", .{opcode});

            std.debug.print("x: {x}\n", .{x});
            std.debug.print("y: {x}\n", .{y});
            std.debug.print("n: {x}\n", .{n});
            std.debug.print("nn: {x}\n", .{nn});
            std.debug.print("nnn: {x}\n", .{nnn});

            for (0..16) |idx| {
                std.debug.print("v{d}: {x}\n", .{chip8.registers[idx]});
            }

            std.debug.print("i: {x}\n", .{i.*});

            std.debug.print("\n\n", .{});
        }

        switch ((opcode & 0xf000) >> 12) {
            0x0 => {
                if (opcode == 0xe0) {
                    // 0x00E0: clear the display
                    @memset(display, 0);
                    pc.* += 2;
                } else if (opcode == 0xee) {
                    // 0x00EE: return from subroutine
                    chip8.stack_index -= 1;
                    pc.* = chip8.address_stack[chip8.stack_index];
                } else {
                    // 0x0NNN: call machine code subroutine at NNN (idk just copy the other one)
                    chip8.address_stack[chip8.stack_index] = pc.* + 2;
                    chip8.stack_index += 1;
                    pc.* = nnn;
                }
            },
            0x1 => {
                // 0x1NNN: goto NNN
                pc.* = nnn;
            },
            0x2 => {
                // 0x2NNN: call the subroutine NNN
                chip8.address_stack[chip8.stack_index] = pc.* + 2;
                chip8.stack_index += 1;
                pc.* = nnn;
            },
            0x3 => {
                // 0xVXNN: skip the next instruction if VX == NN
                pc.* += if (vx.* == nn) 4 else 2;
            },
            0x4 => {
                // 0xVXNN: skip the next instruction if VX != NN
                pc.* += if (vx.* != nn) 4 else 2;
            },
            0x5 => {
                // 0xVXNN: skip the next instruction if VX == VY
                pc.* += if (vx.* == vy.*) 4 else 2;
            },
            0x6 => {
                // 0x6XNN: set VX to NN
                vx.* = nn;
                pc.* += 2;
            },
            0x7 => {
                // 0x7XNN: add NN to VX (carry flag is not changed)
                vx.* +%= nn;
                pc.* += 2;
            },
            0x8 => {
                switch (n) {
                    0x0 => {
                        // 0x8XY0: set VX to VY
                        vx.* = vy.*;
                    },
                    0x1 => {
                        // 0x8XY1: set VX to VX bit-or VY
                        vx.* |= vy.*;
                    },
                    0x2 => {
                        // 0x8XY2: set VX to VX bit-and VY
                        vx.* &= vy.*;
                    },
                    0x3 => {
                        // 0x8XY3: set VX to VX bit-xor VY
                        vx.* ^= vy.*;
                    },
                    0x4 => {
                        // 0x8XY4: add VY to VX (carry flag changed)
                        const res = vx.* +% vy.*;
                        vf.* = @intFromBool(res < vx.*);
                        vx.* = res;
                    },
                    0x5 => {
                        // 0x8XY5: sub VY from VX (carry flag changed)
                        vf.* = @intFromBool((vx.* >= vy.*));
                        vx.* -%= vy.*;
                    },
                    0x6 => {
                        // 0x8XY6: shift VX to the right (carry flag set to lsb)
                        vf.* = vx.* & 0x01;
                        vx.* >>= 1;
                    },
                    0x7 => {
                        // 0x8XY7: subtract VX from VY, store in VX (carry flag changed)
                        vf.* = @intFromBool((vy.* >= vx.*));
                        vx.* = vy.* -% vx.*;
                    },
                    0xe => {
                        // 0x8XYE: shift VX to the right (carry flag set to lsb)
                        vf.* = vx.* & 0x80;
                        vx.* <<= 1;
                    },
                    else => unknown(opcode),
                }
                pc.* += 2;
            },
            0x9 => {
                // 0x9XY0: skip the next instruction if VX != VY
                pc.* += if (vx.* != vy.*) 4 else 2;
            },
            0xa => {
                // 0xANNN: set the address register to NNN
                i.* = nnn;
                pc.* += 2;
            },
            0xb => {
                // 0xBNNN: jump to address nnn + V0
                pc.* = nnn + chip8.registers[0x0];
                pc.* += 2;
            },
            0xc => {
                // 0xCXNN: VX = rand (0..255) & NN
                vx.* = random.uintAtMost(u8, 255) & nn;
                pc.* += 2;
            },
            0xd => {
                // 0xDXYN: draw sprite into display memory at pixel coordinate VX VY
                // using sprite data starting at I, up to I+N
                vf.* = 0;
                const sprite_data = chip8.memory[i.* .. i.* + n];
                var display_index: usize = (vx.* / 8) + (vy.* * 8);

                const first_index = display_index;

                row: for (sprite_data) |sprite_byte| {
                    var display_byte = &display[display_index];
                    var display_bit = vx.* % 8;

                    for (0..8) |sprite_bit| {
                        defer display_bit += 1;
                        if (display_bit == 8) {
                            display_bit = 0;
                            const next_index = (display_index + 1) % 0xff;
                            display_byte = &display[next_index];
                        }
                        if (display_index < first_index) {
                            break :row;
                        }

                        if (debug) {
                            std.debug.print(
                                "sprite bit: {d}, display_index: {d}, display byte: {p}, display bit: {d}\n",
                                .{ sprite_bit, display_index, display_byte, display_bit },
                            );
                        }

                        const saved = display_byte.*;
                        const display_shift: u3 = @intCast(7 - display_bit);
                        const sprite_shift: u3 = @intCast(7 - sprite_bit);

                        const sprite_bit_as_lsb = (sprite_byte >> sprite_shift) & 0x01;
                        display_byte.* ^= sprite_bit_as_lsb << display_shift;

                        if (vf.* == 0) {
                            vf.* |= @intFromBool(saved == display_byte.*);
                        }
                    }

                    display_index = (display_index + 8) % 0xff;
                }

                if (debug) {
                    std.debug.print("{any}\n", .{display});
                    std.debug.print("\n", .{});
                }

                pc.* += 2;
            },
            0xe => {
                if (nn == 0x9e) {
                    // 0xEX9E: if key pressed == key code stored in VX skip next instruction
                    pc.* += if (isKeyPressed(vx.*)) 4 else 2;
                } else if (nn == 0xa1) {
                    // 0xEXA1: if key pressed != key code stored in VX skip next instruction
                    pc.* += if (!isKeyPressed(vx.*)) 4 else 2;
                } else {
                    unknown(opcode);
                }
            },
            0xf => {
                switch (nn) {
                    0x07 => {
                        // 0xFX07: store the timer value in VX
                        vx.* = chip8.delay_timer;
                    },
                    0x0a => {
                        // 0xFX0A: wait for the next key press, and store it in VX
                        vx.* = waitNextKeyPress();
                    },
                    0x15 => {
                        // 0xFX15: set the delay timer to VX
                        chip8.delay_timer = vx.*;
                    },
                    0x18 => {
                        // 0xFX18: set the sound timer to VX
                        chip8.sound_timer = vx.*;
                    },
                    0x1e => {
                        // 0xFX1E: add VX to I
                        i.* += vx.*;
                    },
                    0x29 => {
                        // 0xFX29: set I to the character address for VX
                        i.* = 0x50 + ((vx.* & 0x0f) * 4);
                    },
                    0x33 => {
                        // 0xFX33: store three digit decimal of VX to I, I+1, I+2
                        var num = vx.*;
                        for (0..3) |count| {
                            chip8.memory[i.* + (2 - count)] = num % 10;
                            num /= 10;
                        }
                    },
                    0x55 => {
                        // 0xFX55: store registers up to VX into memory, from I

                        for (0..x + 1) |index| {
                            chip8.memory[i.* + index] = chip8.registers[index];
                        }
                    },
                    0x65 => {
                        // 0xFX65: store memory up to I+X into registers V0 to VX
                        for (0..x + 1) |index| {
                            chip8.registers[index] = chip8.memory[i.* + index];
                        }
                    },
                    else => unknown(opcode),
                }
                pc.* += 2;
            },
            else => unknown(opcode),
        }
    }

    fn unimpl(op: u16) void {
        std.debug.print("op 0x{x:04} not implemented\n", .{op});
        @panic(":)");
    }

    fn unknown(op: u16) void {
        std.debug.print("op 0x{x:04} is not valid\n", .{op});
        @panic(":(");
    }
};

// TODO: implement
fn isKeyPressed(key_code: u8) bool {
    _ = key_code;
    return false;
}

// TODO: implement
fn waitNextKeyPress() u8 {
    return 0x00;
}

pub fn main(init: std.process.Init) !void {
    defer _ = init.arena.reset(.free_all);

    var chip8: Chip8 = .{};
    var rng = std.Random.DefaultPrng.init(
        @bitCast(std.Io.Timestamp.now(
            init.io,
            .awake,
        ).toMilliseconds()),
    );
    random = rng.random();

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) {
        std.debug.print("chip8z rom_file_path\n", .{});
        return;
    }

    const rom: Rom = try .load(init.arena.allocator(), init.io, args[1]);
    defer rom.unload(init.arena.allocator());

    const font = [_]u8{
        0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
        0x20, 0x60, 0x20, 0x20, 0x70, // 1
        0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
        0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
        0x90, 0x90, 0xF0, 0x10, 0x10, // 4
        0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
        0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
        0xF0, 0x10, 0x20, 0x40, 0x40, // 7
        0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
        0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
        0xF0, 0x90, 0xF0, 0x90, 0x90, // A
        0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
        0xF0, 0x80, 0x80, 0x80, 0xF0, // C
        0xE0, 0x90, 0x90, 0x90, 0xE0, // D
        0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    };

    chip8.loadRom(&rom);
    chip8.loadFont(&font);

    var stdout_buf: [1024 * 3]u8 = @splat(0);
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buf);

    var display_cache: [0x100]u8 = @splat(0);

    var step_timestamp = std.Io.Timestamp.now(init.io, .awake);
    var step_count: u64 = 0;
    const steps_per_timer = cpu_hz / 60;

    while (true) {
        if (cli) {
            try stdout.interface.print("\x1b[H", .{});
            try stdout.interface.defaultFlush();
        }

        if (cli) {
            try stdout.interface.print(
                "step count: {d}\n",
                .{step_count},
            );
            try stdout.interface.defaultFlush();
        }

        const now = std.Io.Timestamp.now(init.io, .awake);
        const dt = now.nanoseconds - step_timestamp.nanoseconds;

        if (cli) {
            try stdout.interface.defaultFlush();
            try stdout.interface.print(
                "render delta: {d}\n",
                .{dt},
            );
        }

        // 500hz: step cpu
        if (dt < std.time.ns_per_s / cpu_hz) {
            continue;
        }

        chip8.step();
        step_count += 1;
        step_timestamp = now;

        // 60hz: decrement timers > 0; render
        if (step_count % steps_per_timer == 0) {
            chip8.delay_timer -|= 1;
            chip8.sound_timer -|= 1;

            // only re-render if the display has changed
            // smart price retained-ui
            if (!std.mem.eql(u8, &display_cache, chip8.memory[0xf00..])) {
                @memcpy(&display_cache, chip8.memory[0xf00..]);

                if (cli) {
                    try stdout.interface.print("\n", .{});
                    for (display_cache, 0..) |byte, i| {
                        if (i % 8 == 0) {
                            try stdout.interface.print("\n", .{});
                        }
                        for (0..8) |bit| {
                            const shift: u3 = @intCast(7 - bit);
                            try stdout.interface.print(
                                "{s}",
                                .{if ((byte >> shift) & 0x01 == 1) "y " else ". "},
                            );
                        }
                    }
                    try stdout.interface.print("\n", .{});
                }
                try stdout.interface.defaultFlush();
            }
        }
    }

    if (cli) {
        try stdout.interface.print("\n", .{});
        try stdout.interface.defaultFlush();
    }
}
