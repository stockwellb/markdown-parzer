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
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();
    const writer = output.writer();
    
    try writer.print(".{{\n", .{});
    for (tokens, 0..) |token, i| {
        if (i > 0) try writer.print(",\n", .{});
        
        // Escape the value for ZON format
        var escaped_value = std.ArrayList(u8).init(allocator);
        defer escaped_value.deinit();
        try escapeZonString(token.value, escaped_value.writer());
        
        try writer.print("    .{{ .type = \"{s}\", .value = \"{s}\", .line = {d}, .column = {d} }}", .{
            @tagName(token.type),
            escaped_value.items,
            token.line,
            token.column,
        });
    }
    try writer.print("\n}}\n", .{});
    
    try std.fs.File.stdout().writeAll(output.items);
}

fn escapeZonString(s: []const u8, writer: anytype) !void {
    for (s) |c| {
        switch (c) {
            '"' => try writer.print("\\\"", .{}),
            '\\' => try writer.print("\\\\", .{}),
            '\n' => try writer.print("\\n", .{}),
            '\t' => try writer.print("\\t", .{}),
            '\r' => try writer.print("\\r", .{}),
            else => try writer.writeByte(c),
        }
    }
}
