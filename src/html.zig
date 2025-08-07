//! HTML renderer for Markdown AST
//!
//! This module converts parsed Markdown AST nodes into HTML output.
//! It supports multiple rendering modes including full HTML documents
//! with templates, custom templates, and body-only rendering.
//!
//! ## Features
//! - Full HTML5 document generation with responsive meta tags
//! - Custom template support with {content} placeholder
//! - Body-only rendering for embedding in existing pages
//! - Recursive rendering of nested elements
//! - ZON AST deserialization and rendering
//!
//! ## Rendering Modes
//! 1. **Default Template**: Modern HTML5 with viewport meta tags
//! 2. **Custom Template**: User-provided HTML with {content} placeholder
//! 3. **Body Only**: Just the converted content, no HTML wrapper
//!
//! ## Usage
//! ```zig
//! // Default template
//! const html = try renderToHtml(allocator, ast);
//!
//! // Custom template
//! const custom = try renderToHtmlWithTemplate(allocator, ast, template);
//!
//! // Body only
//! const body = try renderToHtmlBody(allocator, ast);
//! ```

const std = @import("std");
const parser = @import("parser.zig");

const Node = parser.Node;
const NodeType = parser.NodeType;

/// Default HTML5 template with modern meta tags
///
/// This template provides:
/// - HTML5 doctype
/// - UTF-8 encoding
/// - Responsive viewport settings
/// - IE compatibility meta tag
/// - {content} placeholder for rendered Markdown
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
///
/// Renders the AST into a complete HTML5 document using the
/// built-in default template. This is the simplest way to
/// generate a complete, standalone HTML file.
///
/// Parameters:
///   - allocator: Memory allocator for the HTML string
///   - ast: The root AST node to render
///
/// Returns: Complete HTML document as a string
///
/// Error: Returns error.OutOfMemory if allocation fails
pub fn renderToHtml(allocator: std.mem.Allocator, ast: *const Node) ![]u8 {
    return renderToHtmlWithTemplate(allocator, ast, default_html_template);
}

/// Convert an AST node to HTML with custom template
///
/// Renders the AST into HTML and inserts it into a custom template
/// at the {content} placeholder location. If no placeholder is found,
/// returns just the rendered content.
///
/// Template Example:
/// ```html
/// <!DOCTYPE html>
/// <html>
/// <head><title>My Doc</title></head>
/// <body>
///   <header>Site Header</header>
///   {content}
///   <footer>Site Footer</footer>
/// </body>
/// </html>
/// ```
///
/// Parameters:
///   - allocator: Memory allocator for the HTML string
///   - ast: The root AST node to render
///   - template: HTML template with {content} placeholder
///
/// Returns: HTML document with content inserted into template
///
/// Error: Returns error.OutOfMemory if allocation fails
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

/// Convert an AST node to HTML body content only
///
/// Renders just the Markdown content as HTML without any document
/// wrapper. Perfect for embedding Markdown content into existing
/// web pages or content management systems.
///
/// Parameters:
///   - allocator: Memory allocator for the HTML string
///   - ast: The root AST node to render
///
/// Returns: HTML content without document wrapper
///
/// Error: Returns error.OutOfMemory if allocation fails
pub fn renderToHtmlBody(allocator: std.mem.Allocator, ast: *const Node) ![]u8 {
    var html = std.ArrayList(u8).init(allocator);
    const writer = html.writer();

    try renderNode(writer, ast);

    return html.toOwnedSlice();
}

/// Render a single AST node to HTML writer
///
/// Recursively renders an AST node and all its children to the
/// provided writer. This is the core rendering function that
/// handles all node types and their HTML representations.
///
/// Supported Elements:
/// - document: Container only, renders children
/// - heading: <h1> through <h6> based on level
/// - paragraph: <p> tags
/// - text: Plain text content
/// - strong: <strong> tags
/// - emphasis: <em> tags
/// - code: <code> for inline code
/// - code_block: <pre><code> for code blocks
/// - list: <ul> for unordered lists
/// - list_item: <li> tags
/// - blockquote: <blockquote> tags
/// - horizontal_rule: <hr> tags
/// - link: <a> tags (basic implementation)
/// - image: <img> tags (basic implementation)
///
/// Parameters:
///   - writer: Any writer that implements the Writer interface
///   - node: The AST node to render
///
/// Error: Returns writer errors if writing fails
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

/// Parse ZON AST and render to HTML with default template
///
/// Convenience function that deserializes a ZON-formatted AST
/// and renders it to HTML. This enables the HTML renderer to
/// work directly with ZON output from the parser.
///
/// Parameters:
///   - allocator: Memory allocator
///   - zon_ast: ZON-formatted AST string
///
/// Returns: Complete HTML document
///
/// Error: Returns error.InvalidZon if ZON parsing fails
pub fn zonAstToHtml(allocator: std.mem.Allocator, zon_ast: []const u8) ![]u8 {
    // Parse the ZON AST back into a Node structure
    var ast = try parseZonAst(allocator, zon_ast);
    defer ast.deinit(allocator);

    return renderToHtml(allocator, &ast);
}

/// Parse ZON AST and render to HTML with custom template
///
/// Deserializes a ZON-formatted AST and renders it using a
/// custom HTML template with {content} placeholder.
///
/// Parameters:
///   - allocator: Memory allocator
///   - zon_ast: ZON-formatted AST string
///   - template: HTML template with {content} placeholder
///
/// Returns: HTML with content inserted into template
///
/// Error: Returns error.InvalidZon if ZON parsing fails
pub fn zonAstToHtmlWithTemplate(allocator: std.mem.Allocator, zon_ast: []const u8, template: []const u8) ![]u8 {
    // Parse the ZON AST back into a Node structure
    var ast = try parseZonAst(allocator, zon_ast);
    defer ast.deinit(allocator);

    return renderToHtmlWithTemplate(allocator, &ast, template);
}

/// Parse ZON AST and render to HTML body only
///
/// Deserializes a ZON-formatted AST and renders just the
/// content without any HTML document wrapper.
///
/// Parameters:
///   - allocator: Memory allocator
///   - zon_ast: ZON-formatted AST string
///
/// Returns: HTML content without wrapper
///
/// Error: Returns error.InvalidZon if ZON parsing fails
pub fn zonAstToHtmlBody(allocator: std.mem.Allocator, zon_ast: []const u8) ![]u8 {
    // Parse the ZON AST back into a Node structure
    var ast = try parseZonAst(allocator, zon_ast);
    defer ast.deinit(allocator);

    return renderToHtmlBody(allocator, &ast);
}

/// Legacy JSON support (deprecated)
///
/// This function exists for backward compatibility but is
/// deprecated. Use ZON format instead for better integration
/// with Zig's type system.
///
/// @deprecated Use zonAstToHtml() instead
///
/// Returns: error.JsonDeprecated always
pub fn jsonAstToHtml(allocator: std.mem.Allocator, json_ast: []const u8) ![]u8 {
    return parseJsonAst(allocator, json_ast);
}

/// Internal AST structure for JSON/ZON deserialization
///
/// This intermediate structure is used when parsing serialized
/// AST data. It differs from the main Node struct in that it
/// uses slices instead of ArrayLists for children.
const JsonAstNode = struct {
    type: NodeType,
    content: ?[]const u8 = null,
    level: ?u8 = null,
    children: []JsonAstNode = &[_]JsonAstNode{},

    /// Free resources owned by this JSON AST node
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

    /// Convert JSON AST node to parser Node structure
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

/// ZON AST input structure for deserialization
///
/// Matches the ZON format produced by the parser's astToZon()
/// function. Uses slices for zero-copy parsing.
const ZonAstInput = struct {
    type: NodeType,
    content: ?[]const u8 = null,
    level: ?u8 = null,
    children: []ZonAstInput = &[_]ZonAstInput{},
};

/// Parse a ZON-formatted AST string into a Node structure
///
/// Uses Zig's built-in ZON parser to deserialize the AST.
/// The ZON format preserves enum types and structure better
/// than JSON.
///
/// Parameters:
///   - allocator: Memory allocator for the Node
///   - zon: ZON-formatted AST string
///
/// Returns: Parsed Node structure
///
/// Error: Returns error.InvalidZon if parsing fails
fn parseZonAst(allocator: std.mem.Allocator, zon: []const u8) !Node {
    // Use std.zon.parse.fromSlice for ZON data
    // Need null-terminated string for ZON parser
    const zon_terminated = try allocator.dupeZ(u8, zon);
    defer allocator.free(zon_terminated);

    const parsed = std.zon.parse.fromSlice(ZonAstInput, allocator, zon_terminated, null, .{}) catch return error.InvalidZon;
    defer std.zon.parse.free(allocator, parsed);

    return try zonInputToNode(allocator, parsed);
}

/// Convert ZON input structure to parser Node
///
/// Recursively converts the deserialized ZON structure into
/// the Node format used by the renderer. Handles content
/// duplication and child node creation.
///
/// Parameters:
///   - allocator: Memory allocator
///   - input: Deserialized ZON structure
///
/// Returns: Converted Node structure
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

/// Parse JSON AST (deprecated)
///
/// JSON support is deprecated in favor of ZON format.
/// This function always returns an error.
///
/// @deprecated Use parseZonAst() instead
///
/// Returns: error.JsonDeprecated always
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

