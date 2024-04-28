const std = @import("std");
const c8 = @import("chip8.zig");

pub fn main() !void {
    const rom = "roms/ibm_logo.ch8";
    const file = try std.fs.cwd().openFile(rom, .{});
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

    var mem: [4096]u8 = .{0} ** 4096;
    var dis: [64 * 32]u8 = .{0} ** (64 * 32);

    var chip8: c8.Chip8 = .{
        .memory = mem,
        .stack = mem[0x01bb..],
        .display = dis,
        .cpu = .{
            .memory = &mem,
            .pc = mem[0x0200..],
            .display = &dis,
        },
    };

    @memcpy(chip8.memory[0x0066 .. 0x0066 + font.len], font[0..]);

    _ = try file.readAll(mem[0x0200..]);

    const ns: u64 = @as(u64, @intFromFloat((1.0 / 700.0) * 1000_000)) * 1000;
    var i: usize = 0;

    while (true) {
        if (i >= 64 * 32) {
            i = 0;
            continue;
        }
        if (i % 64 == 0) {
            if (i != 0) {
                std.debug.print("\n", .{});
            }
        }
        if (dis[i] == 0) {
            std.debug.print(" ", .{});
        } else {
            std.debug.print("o", .{});
        }

        i += 1;

        c8.readInstruction(&chip8.cpu);
        std.time.sleep(ns);
    }
}
