const std = @import("std");
const c8 = @import("chip8.zig");
const rl = @import("raylib");

pub fn main() !void {
    const scale = 20;
    const tile_width = scale;
    const tile_height = scale;
    const window_width = 64 * scale;
    const window_height = 32 * scale;

    rl.initWindow(window_width, window_height, "chip8");
    defer rl.closeWindow();

    const tile_black = rl.genImageColor(tile_width, tile_height, rl.Color.maroon);
    const tile_white = rl.genImageColor(tile_width, tile_height, rl.Color.black);

    const tile_black_tex = rl.loadTextureFromImage(tile_black);
    const tile_white_tex = rl.loadTextureFromImage(tile_white);

    tile_black.unload();
    tile_white.unload();

    const rom = "roms/chip8_logo.ch8";
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

    const ns: u64 = 250_000_000;

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        var x: i32 = 0;
        var y: i32 = 0;
        for (dis) |pixel| {
            defer x += 1;
            if (x == 64) {
                x = 0;
                y += tile_height;
            }
            if (pixel == 0) {
                rl.drawTexture(tile_black_tex, x * tile_width, y, rl.Color.white);
            } else {
                rl.drawTexture(tile_white_tex, x * tile_width, y, rl.Color.white);
            }
        }

        c8.readInstruction(&chip8.cpu);
        std.time.sleep(ns);
    }
}
