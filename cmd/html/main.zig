const std = @import("std");
const markdown_parzer = @import("markdown_parzer");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read ZON AST from stdin
    const zon_input = try std.fs.File.stdin().readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(zon_input);

    // Convert ZON AST to HTML using the library
    const html = try markdown_parzer.zonAstToHtml(allocator, zon_input);
    defer allocator.free(html);

    // Output HTML to stdout
    try std.fs.File.stdout().writeAll(html);
}