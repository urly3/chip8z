const std = @import("std");

const debug = false;
const screen_width = 64;
const screen_height = 32;
var random: std.Random = undefined;

const Rom = struct {
    data: []const u8,

    fn load(allocator: std.mem.Allocator, io: std.Io, filename: []const u8) !Rom {
        var file = try std.Io.Dir.cwd().openFile(io, filename, .{});
        var reader = file.reader(io, &.{});
        return .{
            .data = try reader.interface.allocRemaining(allocator, .unlimited),
        };
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

    // load the given rom into memory
    fn loadRom(chip8: *Chip8, rom: *const Rom) void {
        const end = 0x200 + rom.data.len;
        @memcpy(chip8.memory[0x200..end], rom.data);

        if (debug) {
            std.debug.print("{any}\n\n", .{chip8.memory});
        }
    }

    // step through the next instruction in memory
    // at program_counter offset
    //
    // all instructions are 2 bytes long
    fn step(chip8: *Chip8) void {
        const pc = &chip8.program_counter;
        const opcode_bytes = chip8.memory[pc.* .. pc.* + 2];
        const opcode_uint = std.mem.readVarInt(u16, opcode_bytes, .big);

        // nxym
        const x: u4 = @truncate(opcode_uint >> 8);
        const y: u4 = @truncate(opcode_uint >> 4);
        const n: u4 = @truncate(opcode_uint);
        const nn: u8 = @truncate(opcode_uint);
        const nnn: u12 = @truncate(opcode_uint);

        const vx = &chip8.registers[x];
        const vy = &chip8.registers[y];
        const vf = &chip8.registers[0xf];

        const i = &chip8.address_register;

        const display: []u8 = chip8.memory[0xf00..];

        if (debug) {
            std.debug.print("display starts at address: {p}", .{&display[0]});

            std.debug.print("pc: {x}\n", .{pc.*});

            std.debug.print("op bytes: {any}\n", .{opcode_bytes});
            std.debug.print("op uint: {x}\n", .{opcode_uint});

            std.debug.print("x: {x}\n", .{x});
            std.debug.print("y: {x}\n", .{y});
            std.debug.print("n: {x}\n", .{n});
            std.debug.print("nn: {x}\n", .{nn});
            std.debug.print("nnn: {x}\n", .{nnn});

            std.debug.print("vx: {x}\n", .{vx.*});
            std.debug.print("vy: {x}\n", .{vy.*});
            std.debug.print("vf: {x}\n", .{vf.*});

            std.debug.print("i: {x}\n", .{i.*});

            std.debug.print("ms nib: {x}\n", .{(opcode_uint & 0xf000) >> 12});
            std.debug.print("\n\n", .{});
        }

        switch ((opcode_uint & 0xf000) >> 12) {
            0x0 => {
                if (opcode_uint == 0xe0) {
                    // 0x00e0: clear the display
                    @memset(display, 0);
                    pc.* += 2;
                } else if (opcode_uint == 0xee) {
                    // 0x00ee: return from subroutine
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
                // add NN to VX (carry flag is not changed)
                vx.* +%= nn;
                pc.* += 2;
            },
            0x8 => {
                switch (n) {
                    0x0 => {
                        // set VX to VY
                        vx.* = vy.*;
                    },
                    0x1 => {
                        // set VX to VX bit-or VY
                        vx.* |= vy.*;
                    },
                    0x2 => {
                        // set VX to VX bit-and VY
                        vx.* &= vy.*;
                    },
                    0x3 => {
                        // set VX to VX bit-xor VY
                        vx.* ^= vy.*;
                    },
                    0x4 => {
                        // add VY to VX (carry flag changed)
                        const res = vx.* +% vy.*;
                        vf.* = @intFromBool(res < vx.*);
                        vx.* = res;
                    },
                    0x5 => {
                        // sub VY from VX (carry flag changed)
                        vf.* = @intFromBool((vx.* >= vy.*));
                        vx.* -%= vy.*;
                    },
                    0x6 => {
                        // shift VX to the right (carry flag set to lsb)
                        vf.* = vx.* & 0x01;
                        vx.* >>= 1;
                    },
                    0x7 => {
                        // subtract VX from VY, store in VX (carry flag changed)
                        vf.* = @intFromBool((vy.* >= vx.*));
                        vx.* = vy.* -% vx.*;
                    },
                    0xe => {
                        // shift VX to the right (carry flag set to lsb)
                        vf.* = vx.* & 0x80;
                        vx.* <<= 1;
                    },
                    else => unknown(opcode_uint),
                }
                pc.* += 2;
            },
            0x9 => {
                // skip the next instruction if VX != VY
                pc.* += if (vx.* != vy.*) 4 else 2;
            },
            0xa => {
                // 0xANNN: set the address register to NNN
                i.* = nnn;
                pc.* += 2;
            },
            0xb => {
                // jump to address nnn + V0
                pc.* = nnn + chip8.registers[0x0];
                pc.* += 2;
            },
            0xc => {
                // VX = rand (0..255) & NN
                vx.* = random.uintAtMost(u8, 255) & nn;
                pc.* += 2;
            },
            0xd => {
                // 0xDXYN:
                // Draws a sprite at coordinate (VX, VY) that has a width of 8 pixels
                // and a height of N pixels. Each row of 8 pixels is read as bit-coded
                // starting from memory location I; I value does not change after the
                // execution of this instruction. As described above, VF is set to 1 if
                // any screen pixels are flipped from set to unset when the sprite is
                // drawn, and to 0 if that does not happen
                vf.* = 0;
                const sprite_data = chip8.memory[i.* .. i.* + n];
                var display_index: usize = (vx.* / 8) + (vy.* * 8);

                for (sprite_data) |sprite_byte| {
                    var display_byte = &display[display_index];
                    var display_bit = vx.* % 8;

                    for (0..8) |sprite_bit| {
                        if (display_bit == 8) {
                            display_bit = 0;
                            display_byte = &display[display_index + 1];
                        }
                        if (debug) {
                            std.debug.print("sprite bit: {d}, display_index: {d}, display byte: {p}, display bit: {d}\n", .{ sprite_bit, display_index, display_byte, display_bit });
                        }
                        const saved = display_byte.*;
                        const display_shift: u3 = @intCast(7 - display_bit);
                        const sprite_shift: u3 = @intCast(7 - sprite_bit);

                        const sprite_bit_as_lsb = (sprite_byte >> sprite_shift) & 0x01;
                        display_byte.* ^= sprite_bit_as_lsb << display_shift;

                        if (vf.* == 0) {
                            vf.* |= @intFromBool(saved == display_byte.*);
                        }

                        display_bit += 1;
                    }

                    display_index += 8;
                }

                if (debug) {
                    std.debug.print("{any}\n", .{display});
                    std.debug.print("\n", .{});
                }

                pc.* += 2;
            },
            0xe => {
                if (nn == 0x9e) {
                    // if key pressed == key code stored in VX skip next instruction
                    pc.* += if (isKeyPressed(vx.*)) 4 else 2;
                } else if (nn == 0xa1) {
                    // if key pressed != key code stored in VX skip next instruction
                    pc.* += if (!isKeyPressed(vx.*)) 4 else 2;
                } else {
                    unknown(opcode_uint);
                }
            },
            0xf => {
                switch (nn) {
                    0x07 => {
                        // store the timer value in VX
                        vx.* = chip8.delay_timer;
                    },
                    0x0a => {
                        // wait for the next key press, and store it in VX
                        vx.* = waitNextKeyPress();
                    },
                    0x15 => {
                        // set the delay timer to VX
                        chip8.delay_timer = vx.*;
                    },
                    0x18 => {
                        // set the sound timer to VX
                        chip8.sound_timer = vx.*;
                    },
                    0x1e => {
                        // add VX to I
                        i.* += vx.*;
                    },
                    0x29 => {
                        // set I to the character address for VX
                        i.* = 0x50 + ((vx.* & 0x0f) * 4);
                    },
                    0x33 => {

                        // Stores the binary-coded decimal representation of VX,
                        // with the hundreds digit in memory at location in I,
                        // the tens digit at location I+1, and the ones digit at
                        // location I+2
                        var num = vx.*;
                        for (0..3) |count| {
                            chip8.memory[i.* + (2 - count)] = num % 10;
                            num /= 10;
                        }
                    },
                    0x55 => {
                        // Stores from V0 to VX (including VX) in memory,
                        // starting at address I. The offset from I is increased
                        // by 1 for each value written,
                        // but I itself is left unmodified

                        for (0..x + 1) |index| {
                            chip8.memory[i.* + index] = chip8.registers[index];
                        }
                    },
                    0x65 => {
                        // Fills from V0 to VX (including VX) with values from
                        // memory, starting at address I. The offset from I is
                        // increased by 1 for each value read, but
                        // I itself is left unmodified
                        for (0..x + 1) |index| {
                            chip8.registers[index] = chip8.memory[i.* + index];
                        }
                    },
                    else => unknown(opcode_uint),
                }
                pc.* += 2;
            },
            else => unknown(opcode_uint),
        }
    }
};

fn unimpl(op: u16) void {
    std.debug.print("op 0x{x:04} not implemented\n", .{op});
    @panic(":)");
}

fn unknown(op: u16) void {
    std.debug.print("op 0x{x:04} is not valid\n", .{op});
    @panic(":(");
}

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
    var chip8: Chip8 = .{};
    var rng = std.Random.DefaultPrng.init(
        @bitCast(std.Io.Timestamp.now(
            init.io,
            .awake,
        ).toMilliseconds()),
    );
    random = rng.random();

    const rom = try Rom.load(init.arena.allocator(), init.io, "roms/particle_demo_zeroZshadow_2008.ch8");
    chip8.loadRom(&rom);

    var buf: [2046]u8 = @splat(0);
    var stdout = std.Io.File.stdout().writer(init.io, &buf);

    var display_cache: [0x100]u8 = @splat(0);

    var render_timestamp = std.Io.Timestamp.now(init.io, .awake);
    var timers_timestamp = std.Io.Timestamp.now(init.io, .awake);

    while (true) {
        defer stdout.interface.flush() catch {};

        try stdout.interface.print("\x1b[H", .{});
        try stdout.interface.flush();
        const render_delta_time = render_timestamp.untilNow(init.io, .awake).nanoseconds;
        const timers_delta_time = timers_timestamp.untilNow(init.io, .awake).nanoseconds;

        // 60hz: decrement timers > 0
        if (timers_delta_time < 16_000_000) {
            try stdout.interface.print("timers dt: {d}\n", .{render_delta_time});
        } else {
            timers_timestamp = std.Io.Timestamp.now(init.io, .awake);
            chip8.delay_timer -|= 1;
            chip8.sound_timer -|= 1;
        }

        // 1000hz: step cpu
        if (render_delta_time < 1_000_000) {
            try stdout.interface.print("render dt: {d}\n", .{render_delta_time});
            continue;
        } else {
            render_timestamp = std.Io.Timestamp.now(init.io, .awake);
        }

        chip8.step();

        if (!std.mem.eql(u8, &display_cache, chip8.memory[0xf00..])) {
            @memcpy(&display_cache, chip8.memory[0xf00..]);
            try stdout.interface.print("\n", .{});
            for (display_cache, 0..) |byte, i| {
                if (i % 8 == 0) {
                    try stdout.interface.print("\n", .{});
                }
                for (0..8) |bit| {
                    const shift: u3 = @intCast(7 - bit);
                    try stdout.interface.print("{s}", .{if ((byte >> shift) & 0x01 == 1) "X " else ". "});
                }
            }
            try stdout.interface.print("\n", .{});
        }
    }

    try stdout.interface.print("\n", .{});
    try stdout.interface.flush();
    _ = init.arena.reset(.free_all);
}
