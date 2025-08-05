const std = @import("std");
const markdown_parzer = @import("markdown_parzer");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Check for template file argument
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    var template: ?[]u8 = null;
    defer if (template) |t| allocator.free(t);
    
    // If template file provided as argument, read it
    if (args.len > 1) {
        if (std.mem.eql(u8, args[1], "--body-only")) {
            // Special flag for body-only output
            template = try allocator.dupe(u8, "");
        } else {
            // Read template file
            if (std.fs.cwd().openFile(args[1], .{})) |file| {
                defer file.close();
                template = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
            } else |err| {
                std.debug.print("Warning: Could not open template file '{s}': {}\n", .{args[1], err});
                std.debug.print("Using default template.\n", .{});
                template = null;
            }
        }
    }

    // Read ZON AST from stdin
    const zon_input = try std.fs.File.stdin().readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(zon_input);

    // Convert ZON AST to HTML using the library
    const html = if (template) |tmpl| blk: {
        if (tmpl.len == 0) {
            // Body-only mode
            break :blk try markdown_parzer.zonAstToHtmlBody(allocator, zon_input);
        } else {
            // Custom template mode
            break :blk try markdown_parzer.zonAstToHtmlWithTemplate(allocator, zon_input, tmpl);
        }
    } else try markdown_parzer.zonAstToHtml(allocator, zon_input);
    
    defer allocator.free(html);

    // Output HTML to stdout
    try std.fs.File.stdout().writeAll(html);
}