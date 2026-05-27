const std = @import("std");

const Rom = struct {
    //
};

const Chip8 = struct {
    memory: [0x1000]u8 = @splat(2),
    registers: [0x10]u8 = @splat(0),
    call_stack: [0x60]u8 = @splat(0),
    display: []u1 = undefined,

    program_counter: u16 = 0x200,
    address_register: u12 = 0,

    fn init() Chip8 {
        var r: Chip8 = .{};
        r.display = @ptrCast(r.memory[0xf00..]);
        return r;
    }

    // load the given rom into memory
    fn loadRom(chip8: *Chip8, rom: *Rom) !void {
        _ = chip8;
        _ = rom;
        //
    }

    // run the rom in memory
    fn run(chip8: *Chip8) !void {

        // loop here for now
        // go through the program memory
        // executing instructions
        while (true) {
            const pc = chip8.program_counter;
            const opcode_bytes = chip8.memory[pc .. pc + 2];

            switch (opcode_bytes[0]) {
                0x0 => {
                    unimpl(std.mem.readVarInt(u16, opcode_bytes, .big));
                },
                0x1 => {
                    unimpl(std.mem.readVarInt(u16, opcode_bytes, .big));
                },
                0x2 => {
                    unimpl(std.mem.readVarInt(u16, opcode_bytes, .big));
                },
                0x3 => {
                    unimpl(std.mem.readVarInt(u16, opcode_bytes, .big));
                },
                0x4 => {
                    unimpl(std.mem.readVarInt(u16, opcode_bytes, .big));
                },
                0x5 => {
                    unimpl(std.mem.readVarInt(u16, opcode_bytes, .big));
                },
                0x6 => {
                    unimpl(std.mem.readVarInt(u16, opcode_bytes, .big));
                },
                0x7 => {
                    unimpl(std.mem.readVarInt(u16, opcode_bytes, .big));
                },
                0x8 => {
                    unimpl(std.mem.readVarInt(u16, opcode_bytes, .big));
                },
                0x9 => {
                    unimpl(std.mem.readVarInt(u16, opcode_bytes, .big));
                },
                0xa => {
                    unimpl(std.mem.readVarInt(u16, opcode_bytes, .big));
                },
                0xb => {
                    unimpl(std.mem.readVarInt(u16, opcode_bytes, .big));
                },
                0xc => {
                    unimpl(std.mem.readVarInt(u16, opcode_bytes, .big));
                },
                0xd => {
                    unimpl(std.mem.readVarInt(u16, opcode_bytes, .big));
                },
                0xe => {
                    unimpl(std.mem.readVarInt(u16, opcode_bytes, .big));
                },
                0xf => {
                    unimpl(std.mem.readVarInt(u16, opcode_bytes, .big));
                },
                else => @panic("unknown instruction"),
            }
        }
    }
};

fn unimpl(op: u16) void {
    std.debug.print("op 0x{x:04} not implemented\n", .{op});
    @panic(":)");
}

pub fn main(init: std.process.Init) !void {
    _ = init;
    var chip8 = Chip8.init();

    try chip8.run();
}
