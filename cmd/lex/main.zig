const std = @import("std");
const markdown_parzer = @import("markdown_parzer");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read from stdin
    const stdin = std.io.getStdIn().reader();
    const contents = try stdin.readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(contents);

    // Tokenize the input
    const tokens = try markdown_parzer.tokenize(allocator, contents);
    defer allocator.free(tokens);

    // Output tokens as JSON to stdout for piping to parser
    const stdout = std.io.getStdOut().writer();
    try stdout.print("[", .{});
    for (tokens, 0..) |token, i| {
        if (i > 0) try stdout.print(",", .{});
        try stdout.print("{{\"type\":\"{s}\",\"value\":\"{s}\",\"line\":{d},\"column\":{d}}}", .{
            @tagName(token.type),
            escapeJsonString(token.value),
            token.line,
            token.column,
        });
    }
    try stdout.print("]\n", .{});
}

fn escapeJsonString(s: []const u8) []const u8 {
    // Simple escaping for common cases - in a real implementation you'd want more robust escaping
    if (std.mem.eql(u8, s, "\n")) return "\\n";
    if (std.mem.eql(u8, s, "\t")) return "\\t";
    if (std.mem.eql(u8, s, "\"")) return "\\\"";
    if (std.mem.eql(u8, s, "\\")) return "\\\\";
    return s;
}
