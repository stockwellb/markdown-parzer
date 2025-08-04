const std = @import("std");
const parser = @import("parser.zig");

const Node = parser.Node;
const NodeType = parser.NodeType;

/// Convert an AST node to HTML
pub fn renderToHtml(allocator: std.mem.Allocator, ast: *const Node) ![]u8 {
    var html = std.ArrayList(u8).init(allocator);
    var writer = html.writer();
    
    try writer.print("<!DOCTYPE html>\n<html>\n<head>\n<title>Parsed Markdown</title>\n</head>\n<body>\n", .{});
    
    try renderNode(writer, ast);
    
    try writer.print("</body>\n</html>\n", .{});
    
    return html.toOwnedSlice();
}

/// Render a single AST node to HTML writer  
pub fn renderNode(writer: anytype, node: *const Node) !void {
    switch (node.type) {
        .document => {
            for (node.children.items) |child| {
                try renderNode(writer, child);
            }
        },
        .heading => {
            const level = node.level orelse 1;
            try writer.print("<h{d}>", .{level});
            if (node.content) |content| {
                try writer.print("{s}", .{content});
            }
            for (node.children.items) |child| {
                try renderNode(writer, child);
            }
            try writer.print("</h{d}>\n", .{level});
        },
        .paragraph => {
            try writer.print("<p>", .{});
            if (node.content) |content| {
                try writer.print("{s}", .{content});
            }
            for (node.children.items) |child| {
                try renderNode(writer, child);
            }
            try writer.print("</p>\n", .{});
        },
        .text => {
            if (node.content) |content| {
                try writer.print("{s}", .{content});
            }
        },
        .strong => {
            try writer.print("<strong>", .{});
            if (node.content) |content| {
                try writer.print("{s}", .{content});
            }
            for (node.children.items) |child| {
                try renderNode(writer, child);
            }
            try writer.print("</strong>", .{});
        },
        .emphasis => {
            try writer.print("<em>", .{});
            if (node.content) |content| {
                try writer.print("{s}", .{content});
            }
            for (node.children.items) |child| {
                try renderNode(writer, child);
            }
            try writer.print("</em>", .{});
        },
        .code => {
            try writer.print("<code>", .{});
            if (node.content) |content| {
                try writer.print("{s}", .{content});
            }
            try writer.print("</code>", .{});
        },
        .code_block => {
            try writer.print("<pre><code>", .{});
            if (node.content) |content| {
                try writer.print("{s}", .{content});
            }
            try writer.print("</code></pre>\n", .{});
        },
        .list => {
            try writer.print("<ul>\n", .{});
            for (node.children.items) |child| {
                try renderNode(writer, child);
            }
            try writer.print("</ul>\n", .{});
        },
        .list_item => {
            try writer.print("<li>", .{});
            if (node.content) |content| {
                try writer.print("{s}", .{content});
            }
            for (node.children.items) |child| {
                try renderNode(writer, child);
            }
            try writer.print("</li>\n", .{});
        },
        .blockquote => {
            try writer.print("<blockquote>", .{});
            if (node.content) |content| {
                try writer.print("{s}", .{content});
            }
            for (node.children.items) |child| {
                try renderNode(writer, child);
            }
            try writer.print("</blockquote>\n", .{});
        },
        .horizontal_rule => {
            try writer.print("<hr>\n", .{});
        },
        .link => {
            // TODO: Handle link URL and text properly from AST
            try writer.print("<a href=\"#\">", .{});
            if (node.content) |content| {
                try writer.print("{s}", .{content});
            }
            for (node.children.items) |child| {
                try renderNode(writer, child);
            }
            try writer.print("</a>", .{});
        },
        .image => {
            // TODO: Handle image URL and alt text properly from AST
            try writer.print("<img src=\"#\" alt=\"", .{});
            if (node.content) |content| {
                try writer.print("{s}", .{content});
            }
            try writer.print("\">", .{});
        },
    }
}

/// Parse JSON AST and render to HTML
/// This is a convenience function that combines JSON parsing + HTML rendering
pub fn jsonAstToHtml(allocator: std.mem.Allocator, json_ast: []const u8) ![]u8 {
    // Parse the JSON AST back into a Node structure
    var ast = try parseJsonAst(allocator, json_ast);
    defer ast.deinit(allocator);
    
    return renderToHtml(allocator, &ast);
}

// Simple AST structure for JSON parsing (separate from the main parser Node)
const JsonAstNode = struct {
    type: NodeType,
    content: ?[]const u8 = null,
    level: ?u8 = null,
    children: []JsonAstNode = &[_]JsonAstNode{},
    
    fn deinit(self: *JsonAstNode, allocator: std.mem.Allocator) void {
        if (self.content) |content| {
            allocator.free(content);
        }
        for (self.children) |*child| {
            child.deinit(allocator);
        }
        if (self.children.len > 0) {
            allocator.free(self.children);
        }
    }
    
    fn toParserNode(self: *const JsonAstNode, allocator: std.mem.Allocator) !Node {
        var node = Node.init(allocator, self.type);
        
        if (self.content) |content| {
            node.content = try allocator.dupe(u8, content);
        }
        
        node.level = self.level;
        
        for (self.children) |*child| {
            const child_node = try allocator.create(Node);
            child_node.* = try child.toParserNode(allocator);
            try node.children.append(child_node);
        }
        
        return node;
    }
};

fn parseJsonAst(allocator: std.mem.Allocator, json: []const u8) !Node {
    // Very simplified JSON parsing for our AST format
    // In a real implementation, you'd use a proper JSON parser
    
    var json_node = JsonAstNode{ .type = .document };
    
    // Extract type
    if (std.mem.indexOf(u8, json, "\"type\":\"")) |type_start| {
        const type_value_start = type_start + 8;
        if (std.mem.indexOf(u8, json[type_value_start..], "\"")) |type_end| {
            const type_str = json[type_value_start..type_value_start + type_end];
            json_node.type = std.meta.stringToEnum(NodeType, type_str) orelse .document;
        }
    }
    
    // Extract content if present
    if (std.mem.indexOf(u8, json, "\"content\":\"")) |content_start| {
        const content_value_start = content_start + 11;
        if (std.mem.indexOf(u8, json[content_value_start..], "\"")) |content_end| {
            const content_str = json[content_value_start..content_value_start + content_end];
            json_node.content = try allocator.dupe(u8, content_str);
        }
    }
    
    // Extract level if present
    if (std.mem.indexOf(u8, json, "\"level\":")) |level_start| {
        const level_value_start = level_start + 8;
        var level_end = level_value_start;
        while (level_end < json.len and json[level_end] != ',' and json[level_end] != '}') {
            level_end += 1;
        }
        const level_str = json[level_value_start..level_end];
        json_node.level = std.fmt.parseInt(u8, level_str, 10) catch null;
    }
    
    const node = try json_node.toParserNode(allocator);
    json_node.deinit(allocator);
    return node;
}

test "render empty document" {
    const allocator = std.testing.allocator;
    
    var root = Node.init(allocator, .document);
    defer root.deinit(allocator);
    
    const html = try renderToHtml(allocator, &root);
    defer allocator.free(html);
    
    try std.testing.expect(std.mem.indexOf(u8, html, "<!DOCTYPE html>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<body>") != null);
}