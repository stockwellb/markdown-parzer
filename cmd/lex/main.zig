const std = @import("std");
const markdown_parzer = @import("markdown_parzer");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read from stdin
    const contents = try std.fs.File.stdin().readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(contents);

    // Tokenize the input
    const tokens = try markdown_parzer.tokenize(allocator, contents);
    defer allocator.free(tokens);

    // Output tokens as ZON to stdout for piping to parser
    const zon_output = try markdown_parzer.tokensToZon(allocator, tokens);
    defer allocator.free(zon_output);
    
    try std.fs.File.stdout().writeAll(zon_output);
}
