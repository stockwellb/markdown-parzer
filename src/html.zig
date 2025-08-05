const std = @import("std");
const parser = @import("parser.zig");

const Node = parser.Node;
const NodeType = parser.NodeType;

/// Default HTML template
pub const default_html_template =
    \\<!DOCTYPE html>
    \\<html lang="en">
    \\<head>
    \\<meta charset="UTF-8">
    \\<meta name="viewport" content="width=device-width, initial-scale=1.0">
    \\<meta http-equiv="X-UA-Compatible" content="ie=edge">
    \\<title>Parsed Markdown</title>
    \\</head>
    \\<body>
    \\{content}
    \\</body>
    \\</html>
    \\
;

/// Convert an AST node to HTML with default template
pub fn renderToHtml(allocator: std.mem.Allocator, ast: *const Node) ![]u8 {
    return renderToHtmlWithTemplate(allocator, ast, default_html_template);
}

/// Convert an AST node to HTML with custom template
/// Template should contain {content} placeholder where the rendered markdown will be inserted
pub fn renderToHtmlWithTemplate(allocator: std.mem.Allocator, ast: *const Node, template: []const u8) ![]u8 {
    // First render the content
    const content = try renderToHtmlBody(allocator, ast);
    defer allocator.free(content);

    // Find {content} placeholder in template
    const placeholder = "{content}";
    const index = std.mem.indexOf(u8, template, placeholder);

    if (index) |idx| {
        // Build the final HTML with template
        var html = std.ArrayList(u8).init(allocator);
        try html.appendSlice(template[0..idx]);
        try html.appendSlice(content);
        try html.appendSlice(template[idx + placeholder.len ..]);
        return html.toOwnedSlice();
    } else {
        // No placeholder found, just return the content
        return allocator.dupe(u8, content);
    }
}

/// Convert an AST node to HTML body only (no wrapper)
pub fn renderToHtmlBody(allocator: std.mem.Allocator, ast: *const Node) ![]u8 {
    var html = std.ArrayList(u8).init(allocator);
    const writer = html.writer();

    try renderNode(writer, ast);

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

/// Parse ZON AST and render to HTML
/// This is a convenience function that combines ZON parsing + HTML rendering
pub fn zonAstToHtml(allocator: std.mem.Allocator, zon_ast: []const u8) ![]u8 {
    // Parse the ZON AST back into a Node structure
    var ast = try parseZonAst(allocator, zon_ast);
    defer ast.deinit(allocator);

    return renderToHtml(allocator, &ast);
}

/// Parse ZON AST and render to HTML with custom template
pub fn zonAstToHtmlWithTemplate(allocator: std.mem.Allocator, zon_ast: []const u8, template: []const u8) ![]u8 {
    // Parse the ZON AST back into a Node structure
    var ast = try parseZonAst(allocator, zon_ast);
    defer ast.deinit(allocator);

    return renderToHtmlWithTemplate(allocator, &ast, template);
}

/// Parse ZON AST and render to HTML body only
pub fn zonAstToHtmlBody(allocator: std.mem.Allocator, zon_ast: []const u8) ![]u8 {
    // Parse the ZON AST back into a Node structure
    var ast = try parseZonAst(allocator, zon_ast);
    defer ast.deinit(allocator);

    return renderToHtmlBody(allocator, &ast);
}

/// Legacy function name for backward compatibility
pub fn jsonAstToHtml(allocator: std.mem.Allocator, json_ast: []const u8) ![]u8 {
    return parseJsonAst(allocator, json_ast);
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

// ZON AST input structure
const ZonAstInput = struct {
    type: NodeType,
    content: ?[]const u8 = null,
    level: ?u8 = null,
    children: []ZonAstInput = &[_]ZonAstInput{},
};

fn parseZonAst(allocator: std.mem.Allocator, zon: []const u8) !Node {
    // Use std.zon.parse.fromSlice for ZON data
    // Need null-terminated string for ZON parser
    const zon_terminated = try allocator.dupeZ(u8, zon);
    defer allocator.free(zon_terminated);

    const parsed = std.zon.parse.fromSlice(ZonAstInput, allocator, zon_terminated, null, .{}) catch return error.InvalidZon;
    defer std.zon.parse.free(allocator, parsed);

    return try zonInputToNode(allocator, parsed);
}

fn zonInputToNode(allocator: std.mem.Allocator, input: ZonAstInput) !Node {
    // Get node type directly from enum
    const node_type = input.type;

    var node = Node.init(allocator, node_type);

    // Set content if present
    if (input.content) |content| {
        node.content = try allocator.dupe(u8, content);
    }

    // Set level if present
    node.level = input.level;

    // Convert children
    for (input.children) |child_input| {
        const child_node = try allocator.create(Node);
        child_node.* = try zonInputToNode(allocator, child_input);
        try node.children.append(child_node);
    }

    return node;
}

fn parseJsonAst(allocator: std.mem.Allocator, json: []const u8) ![]u8 {
    // Legacy JSON support - deprecated, use ZON instead
    _ = json;
    _ = allocator;
    return error.JsonDeprecated;
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

test "render heading" {
    const allocator = std.testing.allocator;

    var root = Node.init(allocator, .document);
    defer root.deinit(allocator);

    const heading = try allocator.create(Node);
    heading.* = Node.init(allocator, .heading);
    heading.level = 2;
    heading.content = try allocator.dupe(u8, "Test Header");

    try root.children.append(heading);

    const html = try renderToHtml(allocator, &root);
    defer allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "<h2>Test Header</h2>") != null);
}

test "render paragraph with inline formatting" {
    const allocator = std.testing.allocator;

    var root = Node.init(allocator, .document);
    defer root.deinit(allocator);

    const para = try allocator.create(Node);
    para.* = Node.init(allocator, .paragraph);

    const text1 = try allocator.create(Node);
    text1.* = Node.init(allocator, .text);
    text1.content = try allocator.dupe(u8, "This is ");

    const bold = try allocator.create(Node);
    bold.* = Node.init(allocator, .strong);
    bold.content = try allocator.dupe(u8, "bold");

    const text2 = try allocator.create(Node);
    text2.* = Node.init(allocator, .text);
    text2.content = try allocator.dupe(u8, " text.");

    try para.children.append(text1);
    try para.children.append(bold);
    try para.children.append(text2);
    try root.children.append(para);

    const html = try renderToHtml(allocator, &root);
    defer allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "<p>This is <strong>bold</strong> text.</p>") != null);
}

test "jsonAstToHtml integration" {
    const allocator = std.testing.allocator;

    const json_ast =
        \\{"type":"document","children":[
        \\{"type":"heading","level":1,"content":"Hello"},
        \\{"type":"paragraph","children":[
        \\{"type":"text","content":"This is "},
        \\{"type":"strong","content":"bold"},
        \\{"type":"text","content":" text."}
        \\]}
        \\]}
    ;

    const html = try jsonAstToHtml(allocator, json_ast);
    defer allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "<h1>Hello</h1>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<p>This is <strong>bold</strong> text.</p>") != null);
}

test "code block rendering issue" {
    const allocator = std.testing.allocator;

    // Test JSON AST that represents a code block (fenced with ```)
    const json_ast =
        \\{"type":"document","children":[
        \\{"type":"code_block","content":"const std = @import(\"std\");\nconst markdown_parzer = @import(\"markdown_parzer\");"}
        \\]}
    ;

    const html = try jsonAstToHtml(allocator, json_ast);
    defer allocator.free(html);

    // Should contain proper code block
    try std.testing.expect(std.mem.indexOf(u8, html, "<pre><code>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "const std = @import(\"std\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "</code></pre>") != null);

    // Should NOT contain broken code like <code></code>`
    try std.testing.expect(std.mem.indexOf(u8, html, "<code></code>`") == null);
}

