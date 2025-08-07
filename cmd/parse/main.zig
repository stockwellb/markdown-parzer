const std = @import("std");
const markdown_parzer = @import("markdown_parzer");

const Token = markdown_parzer.Token;
const TokenType = markdown_parzer.TokenType;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read ZON tokens from stdin
    const zon_input = try std.fs.File.stdin().readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(zon_input);

    // Parse ZON tokens using standard library
    const zon_terminated = try allocator.dupeZ(u8, zon_input);
    defer allocator.free(zon_terminated);
    
    const tokens = std.zon.parse.fromSlice([]Token, allocator, zon_terminated, null, .{}) catch |err| {
        std.debug.print("Failed to parse ZON tokens: {}\n", .{err});
        return;
    };
    defer std.zon.parse.free(allocator, tokens);

    // Parse tokens into MIR
    var parser = markdown_parzer.Parser.init(allocator, tokens);
    const mir = try parser.parse();
    defer {
        mir.deinit(allocator);
        allocator.destroy(mir);
    }

    // Output MIR as ZON to stdout
    const zon_output = try markdown_parzer.mirToZon(allocator, mir);
    defer allocator.free(zon_output);
    
    try std.fs.File.stdout().writeAll(zon_output);
}

