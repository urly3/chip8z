const std = @import("std");

const sdl = @import("zsdl3");
const keycode = sdl.keycode;

const debug = false;

const cpu_hz = 480;

const chip8_width = 64;
const chip8_height = 32;
const render_scale = 10;
const window_width = chip8_width * render_scale;
const window_height = chip8_height * render_scale;

var random: std.Random = undefined;

// 16key pad - 0 through 15
// holy confusing to write
//  1 2 3 C  //  1 2 3 4  //  x 1 2 3
//  4 5 6 D  //  q w e r  //  q w e a
//  7 8 9 E  //  a s d f  //  s d z c
//  a 0 B F  //  z x c v  //  4 r f v
const key_code_to_sdl = [16]sdl.SDL_Scancode{
    keycode.SDL_SCANCODE_X, keycode.SDL_SCANCODE_1, keycode.SDL_SCANCODE_2, keycode.SDL_SCANCODE_3, //
    keycode.SDL_SCANCODE_Q, keycode.SDL_SCANCODE_W, keycode.SDL_SCANCODE_E, keycode.SDL_SCANCODE_A, //
    keycode.SDL_SCANCODE_S, keycode.SDL_SCANCODE_D, keycode.SDL_SCANCODE_Z, keycode.SDL_SCANCODE_C, //
    keycode.SDL_SCANCODE_4, keycode.SDL_SCANCODE_R, keycode.SDL_SCANCODE_F, keycode.SDL_SCANCODE_V, //
};

const Rom = struct {
    data: []const u8,

    fn load(allocator: std.mem.Allocator, io: std.Io, filename: []const u8) !Rom {
        var file = try std.Io.Dir.cwd().openFile(io, filename, .{});
        defer file.close(io);
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
            std.debug.print("pc: {x:02}\n", .{pc.*});
            std.debug.print("op uint: {x:02}\n", .{opcode});
            std.debug.print("x: {x:02}\n", .{x});
            std.debug.print("y: {x:02}\n", .{y});
            std.debug.print("n: {x:02}\n", .{n});
            std.debug.print("nn: {x:02}\n", .{nn});
            std.debug.print("nnn: {x:02}\n", .{nnn});

            for (0..16) |idx| {
                std.debug.print("v{x:02}={x:02}{s} ", .{
                    idx,
                    chip8.registers[idx],
                    if (idx == 0xf) " " else ",",
                });
            }
            std.debug.print("\n", .{});
            std.debug.print("i: {x:02}\n", .{i.*});
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
                    // 0x0NNN: call machine code subroutine at NNN
                    // not sure this should be implemented lol
                    const sr_addr: *const fn () callconv(.c) void = @ptrCast(&memory[nnn]);
                    sr_addr();
                    pc.* += 2;
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
                // 0x3XNN: skip the next instruction if VX == NN
                pc.* += if (vx.* == nn) 4 else 2;
            },
            0x4 => {
                // 0x4XNN: skip the next instruction if VX != NN
                pc.* += if (vx.* != nn) 4 else 2;
            },
            0x5 => {
                // 0x5XNN: skip the next instruction if VX == VY
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
                        const vf_result = @intFromBool(vx.* >= vy.*);
                        vx.* -%= vy.*;
                        vf.* = vf_result;
                    },
                    0x6 => {
                        // 0x8XY6: shift VX to the right (carry flag set to lsb)
                        const vf_result = vx.* & 0x01;
                        vx.* >>= 1;
                        vf.* = vf_result;
                    },
                    0x7 => {
                        // 0x8XY7: subtract VX from VY, store in VX (carry flag changed)
                        const vf_result = @intFromBool(vy.* >= vx.*);
                        vx.* = vy.* -% vx.*;
                        vf.* = vf_result;
                    },
                    0xe => {
                        // 0x8XYE: shift VX to the right (carry flag set to lsb)
                        const vf_result = vx.* & 0x80;
                        vx.* <<= 1;
                        vf.* = vf_result;
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
                const wrapped_vx = vx.* % 64;
                const wrapped_vy = vy.* % 32;
                var display_index: usize = (wrapped_vx / 8) + (wrapped_vy * 8);

                for (sprite_data) |sprite_byte| {
                    var display_byte = &display[display_index];
                    var display_bit = wrapped_vx % 8;
                    var current_index = display_index;

                    for (0..8) |sprite_bit| {
                        defer display_bit += 1;
                        if (display_bit == 8) {
                            display_bit = 0;
                            current_index = (current_index + 1) % 0x100;
                            display_byte = &display[current_index];
                        }

                        if (debug) {
                            std.debug.print(
                                "sprite bit: {x:02}, display_index: {x:02}, display byte: {p}, display bit: {x:02}\n",
                                .{ sprite_bit, current_index, display_byte, display_bit },
                            );
                        }

                        const display_shift: u3 = @intCast(7 - display_bit);
                        const sprite_shift: u3 = @intCast(7 - sprite_bit);

                        const old_bit_lsb = (display_byte.* >> display_shift) & 0x01;
                        const sprite_bit_lsb = (sprite_byte >> sprite_shift) & 0x01;
                        display_byte.* ^= sprite_bit_lsb << display_shift;
                        vf.* |= old_bit_lsb & sprite_bit_lsb;
                    }

                    display_index = (display_index + 8) % 0x100;
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
                        i.* = 0x50 + ((vx.* & 0x0f) * 5);
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

fn isKeyPressed(key_code: u8) bool {
    if (key_code > 0xf) return false;

    const key_state = sdl.getKeyboardState(null) orelse unreachable;
    return key_state[@intCast(key_code_to_sdl[key_code])];
}

fn waitNextKeyPress() u8 {
    var event: sdl.SDL_Event = undefined;
    // infinitely wait for events
    // only leaving when a key is pressed
    while (true) {
        while (sdl.pollEvent(&event)) {
            switch (event.type) {
                sdl.SDL_EVENT_KEY_DOWN => {
                    if (event.key.scancode == sdl.SDL_SCANCODE_1)
                        return 0x1;
                    if (event.key.scancode == sdl.SDL_SCANCODE_2)
                        return 0x2;
                    if (event.key.scancode == sdl.SDL_SCANCODE_3)
                        return 0x3;
                    if (event.key.scancode == sdl.SDL_SCANCODE_4)
                        return 0xc;
                    if (event.key.scancode == sdl.SDL_SCANCODE_Q)
                        return 0x4;
                    if (event.key.scancode == sdl.SDL_SCANCODE_W)
                        return 0x5;
                    if (event.key.scancode == sdl.SDL_SCANCODE_E)
                        return 0x6;
                    if (event.key.scancode == sdl.SDL_SCANCODE_R)
                        return 0xd;
                    if (event.key.scancode == sdl.SDL_SCANCODE_A)
                        return 0x7;
                    if (event.key.scancode == sdl.SDL_SCANCODE_S)
                        return 0x8;
                    if (event.key.scancode == sdl.SDL_SCANCODE_D)
                        return 0x9;
                    if (event.key.scancode == sdl.SDL_SCANCODE_F)
                        return 0xe;
                    if (event.key.scancode == sdl.SDL_SCANCODE_Z)
                        return 0xa;
                    if (event.key.scancode == sdl.SDL_SCANCODE_X)
                        return 0x0;
                    if (event.key.scancode == sdl.SDL_SCANCODE_C)
                        return 0xb;
                    if (event.key.scancode == sdl.SDL_SCANCODE_V)
                        return 0xf;
                },
                else => {},
            }
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) {
        std.debug.print("chip8z rom_file_path\n", .{});
        return;
    }

    if (!sdl.init(sdl.SDL_INIT_VIDEO)) return error.sdlinit;
    defer sdl.quit();

    const window = sdl.createWindow("chip8z", window_width, window_height, sdl.SDL_WINDOW_RESIZABLE) orelse return error.windowinit;
    defer sdl.destroyWindow(window);

    const renderer = sdl.createRenderer(window, null) orelse return error.renderinit;
    defer sdl.destroyRenderer(renderer);

    defer _ = init.arena.reset(.free_all);

    var chip8: Chip8 = .{};
    var rng = std.Random.DefaultPrng.init(
        @bitCast(std.Io.Timestamp.now(
            init.io,
            .awake,
        ).toMilliseconds()),
    );
    random = rng.random();

    const rom: Rom = try .load(init.arena.allocator(), init.io, args[1]);
    defer rom.unload(init.arena.allocator());

    const font: [80]u8 = .{
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
        0xF0, 0x80, 0xF0, 0x80, 0x80, // F
    };
    const font_rounded: [80]u8 = .{
        0x60, 0x90, 0x90, 0x90, 0x60, // 0
        0x20, 0x60, 0x20, 0x20, 0x70, // 1
        0x60, 0x10, 0x60, 0x80, 0x60, // 2
        0x60, 0x10, 0x60, 0x10, 0x60, // 3
        0x90, 0x90, 0x60, 0x10, 0x10, // 4
        0x60, 0x80, 0x60, 0x10, 0x60, // 5
        0x60, 0x80, 0x60, 0x90, 0x60, // 6
        0x60, 0x10, 0x20, 0x40, 0x40, // 7
        0x60, 0x90, 0x60, 0x90, 0x60, // 8
        0x60, 0x90, 0x60, 0x10, 0x60, // 9
        0x60, 0x90, 0x60, 0x90, 0x90, // A
        0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
        0x60, 0x80, 0x80, 0x80, 0x60, // C
        0xE0, 0x90, 0x90, 0x90, 0xE0, // D
        0x60, 0x80, 0x60, 0x80, 0x60, // E
        0x60, 0x80, 0x60, 0x80, 0x80, // F
    };

    chip8.loadRom(&rom);
    chip8.loadFont(if (true) &font_rounded else &font);

    var display_cache: [0x100]u8 = @splat(0);

    var step_timestamp = std.Io.Timestamp.now(init.io, .awake);
    var step_count: u64 = 0;
    const steps_per_timer = cpu_hz / 60;

    outer: while (true) {
        sdl.pumpEvents();
        var event: sdl.SDL_Event = undefined;
        while (sdl.pollEvent(&event)) {
            switch (event.type) {
                sdl.SDL_EVENT_QUIT => {
                    break :outer;
                },
                sdl.SDL_EVENT_KEY_DOWN => {
                    if (event.key.scancode == sdl.SDL_SCANCODE_ESCAPE)
                        break :outer;
                },
                else => {},
            }
        }

        const now = std.Io.Timestamp.now(init.io, .awake);
        const dt = now.nanoseconds - step_timestamp.nanoseconds;

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
                _ = sdl.setRenderDrawColor(
                    renderer,
                    255,
                    150,
                    150,
                    255,
                );
                _ = sdl.renderClear(renderer);

                @memcpy(&display_cache, chip8.memory[0xf00..]);
                const surface = sdl.createSurfaceFrom(chip8_width, chip8_height, 0x11200100, &display_cache, 8) orelse {
                    const error_msg = sdl.getError();
                    if (error_msg) |msg| {
                        std.log.err("{s}", .{msg});
                    }
                    return error.surface;
                };
                defer sdl.destroySurface(surface);

                const palette = sdl.createSurfacePalette(surface) orelse {
                    const error_msg = sdl.getError();
                    if (error_msg) |msg| {
                        std.log.err("{s}", .{msg});
                    }
                    return error.palette;
                };

                palette.colors.?[0] = .{
                    .r = 255,
                    .g = 150,
                    .b = 150,
                    .a = 150,
                };

                const texture = sdl.createTextureFromSurface(renderer, surface) orelse {
                    const error_msg = sdl.getError();
                    if (error_msg) |msg| {
                        std.log.err("{s}", .{msg});
                    }
                    return error.texture;
                };
                defer sdl.destroyTexture(texture);
                _ = sdl.setTextureScaleMode(texture, sdl.SDL_SCALEMODE_PIXELART);

                _ = sdl.renderTexture(renderer, texture, null, null);
                _ = sdl.renderPresent(renderer);
            }
        }
    }
}
