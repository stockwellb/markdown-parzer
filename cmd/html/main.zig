const std = @import("std");
const markdown_parzer = @import("markdown_parzer");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read JSON AST from stdin
    const stdin = std.io.getStdIn().reader();
    const json_input = try stdin.readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(json_input);

    // Convert JSON AST to HTML using the library
    const html = try markdown_parzer.jsonAstToHtml(allocator, json_input);
    defer allocator.free(html);

    // Output HTML to stdout
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{s}", .{html});
}