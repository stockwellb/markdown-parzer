//! HTML renderer for Markdown MIR
//!
//! This module converts parsed Markdown MIR nodes into HTML output.
//! It supports multiple rendering modes including full HTML documents
//! with templates, custom templates, and body-only rendering.
//!
//! ## Features
//! - Full HTML5 document generation with responsive meta tags
//! - Custom template support with {content} placeholder
//! - Body-only rendering for embedding in existing pages
//! - Recursive rendering of nested elements
//! - ZON MIR deserialization and rendering
//!
//! ## Rendering Modes
//! 1. **Default Template**: Modern HTML5 with viewport meta tags
//! 2. **Custom Template**: User-provided HTML with {content} placeholder
//! 3. **Body Only**: Just the converted content, no HTML wrapper
//!
//! ## Usage
//! ```zig
//! // Default template
//! const html = try renderToHtml(allocator, mir);
//!
//! // Custom template
//! const custom = try renderToHtmlWithTemplate(allocator, mir, template);
//!
//! // Body only
//! const body = try renderToHtmlBody(allocator, mir);
//! ```

const std = @import("std");
const parser = @import("parser.zig");

const Mir = parser.Mir;
const MirType = parser.MirType;

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

/// Convert an MIR node to HTML with default template
///
/// Renders the MIR into a complete HTML5 document using the
/// built-in default template. This is the simplest way to
/// generate a complete, standalone HTML file.
///
/// Parameters:
///   - allocator: Memory allocator for the HTML string
///   - mir: The root MIR node to render
///
/// Returns: Complete HTML document as a string
///
/// Error: Returns error.OutOfMemory if allocation fails
pub fn renderToHtml(allocator: std.mem.Allocator, mir: *const Mir) ![]u8 {
    return renderToHtmlWithTemplate(allocator, mir, default_html_template);
}

/// Convert an MIR node to HTML with custom template
///
/// Renders the MIR into HTML and inserts it into a custom template
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
///   - mir: The root MIR node to render
///   - template: HTML template with {content} placeholder
///
/// Returns: HTML document with content inserted into template
///
/// Error: Returns error.OutOfMemory if allocation fails
pub fn renderToHtmlWithTemplate(allocator: std.mem.Allocator, mir: *const Mir, template: []const u8) ![]u8 {
    // First render the content
    const content = try renderToHtmlBody(allocator, mir);
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

/// Convert an MIR node to HTML body content only
///
/// Renders just the Markdown content as HTML without any document
/// wrapper. Perfect for embedding Markdown content into existing
/// web pages or content management systems.
///
/// Parameters:
///   - allocator: Memory allocator for the HTML string
///   - mir: The root MIR node to render
///
/// Returns: HTML content without document wrapper
///
/// Error: Returns error.OutOfMemory if allocation fails
pub fn renderToHtmlBody(allocator: std.mem.Allocator, mir: *const Mir) ![]u8 {
    var html = std.ArrayList(u8).init(allocator);
    const writer = html.writer();

    try renderNode(writer, mir);

    return html.toOwnedSlice();
}

/// Render a single MIR node to HTML writer
///
/// Recursively renders an MIR node and all its children to the
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
///   - node: The MIR node to render
///
/// Error: Returns writer errors if writing fails
pub fn renderNode(writer: anytype, node: *const Mir) !void {
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
            // TODO: Handle link URL and text properly from MIR
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
            // TODO: Handle image URL and alt text properly from MIR
            try writer.print("<img src=\"#\" alt=\"", .{});
            if (node.content) |content| {
                try writer.print("{s}", .{content});
            }
            try writer.print("\">", .{});
        },
    }
}

/// Parse ZON MIR and render to HTML with default template
///
/// Convenience function that deserializes a ZON-formatted MIR
/// and renders it to HTML. This enables the HTML renderer to
/// work directly with ZON output from the parser.
///
/// Parameters:
///   - allocator: Memory allocator
///   - zon_mir: ZON-formatted MIR string
///
/// Returns: Complete HTML document
///
/// Error: Returns error.InvalidZon if ZON parsing fails
pub fn zonMirToHtml(allocator: std.mem.Allocator, zon_mir: []const u8) ![]u8 {
    // Parse the ZON MIR back into a Node structure
    var mir = try parseZonMir(allocator, zon_mir);
    defer mir.deinit(allocator);

    return renderToHtml(allocator, &mir);
}

/// Parse ZON MIR and render to HTML with custom template
///
/// Deserializes a ZON-formatted MIR and renders it using a
/// custom HTML template with {content} placeholder.
///
/// Parameters:
///   - allocator: Memory allocator
///   - zon_mir: ZON-formatted MIR string
///   - template: HTML template with {content} placeholder
///
/// Returns: HTML with content inserted into template
///
/// Error: Returns error.InvalidZon if ZON parsing fails
pub fn zonMirToHtmlWithTemplate(allocator: std.mem.Allocator, zon_mir: []const u8, template: []const u8) ![]u8 {
    // Parse the ZON MIR back into a Node structure
    var mir = try parseZonMir(allocator, zon_mir);
    defer mir.deinit(allocator);

    return renderToHtmlWithTemplate(allocator, &mir, template);
}

/// Parse ZON MIR and render to HTML body only
///
/// Deserializes a ZON-formatted MIR and renders just the
/// content without any HTML document wrapper.
///
/// Parameters:
///   - allocator: Memory allocator
///   - zon_mir: ZON-formatted MIR string
///
/// Returns: HTML content without wrapper
///
/// Error: Returns error.InvalidZon if ZON parsing fails
pub fn zonMirToHtmlBody(allocator: std.mem.Allocator, zon_mir: []const u8) ![]u8 {
    // Parse the ZON MIR back into a Node structure
    var mir = try parseZonMir(allocator, zon_mir);
    defer mir.deinit(allocator);

    return renderToHtmlBody(allocator, &mir);
}


/// Internal MIR structure for ZON deserialization
///
/// This intermediate structure is used when parsing serialized
/// MIR data. It differs from the main Node struct in that it
/// uses slices instead of ArrayLists for children.
const ZonMirNode = struct {
    type: MirType,
    content: ?[]const u8 = null,
    level: ?u8 = null,
    children: []ZonMirNode = &[_]ZonMirNode{},

    /// Free resources owned by this ZON MIR node
    fn deinit(self: *ZonMirNode, allocator: std.mem.Allocator) void {
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

    /// Convert ZON MIR node to parser Node structure
    fn toParserNode(self: *const ZonMirNode, allocator: std.mem.Allocator) !Mir {
        var node = Mir.init(allocator, self.type);

        if (self.content) |content| {
            node.content = try allocator.dupe(u8, content);
        }

        node.level = self.level;

        for (self.children) |*child| {
            const child_node = try allocator.create(Mir);
            child_node.* = try child.toParserNode(allocator);
            try node.children.append(child_node);
        }

        return node;
    }
};

/// ZON MIR input structure for deserialization
///
/// Matches the ZON format produced by the parser's mirToZon()
/// function. Uses slices for zero-copy parsing.
const ZonMirInput = struct {
    type: MirType,
    content: ?[]const u8 = null,
    level: ?u8 = null,
    children: []ZonMirInput = &[_]ZonMirInput{},
};

/// Parse a ZON-formatted MIR string into a Mir structure
///
/// Uses Zig's built-in ZON parser to deserialize the MIR.
/// The ZON format preserves enum types and structure natively.
///
/// Parameters:
///   - allocator: Memory allocator for the Mir
///   - zon: ZON-formatted MIR string
///
/// Returns: Parsed Mir structure
///
/// Error: Returns error.InvalidZon if parsing fails
fn parseZonMir(allocator: std.mem.Allocator, zon: []const u8) !Mir {
    // Use std.zon.parse.fromSlice for ZON data
    // Need null-terminated string for ZON parser
    const zon_terminated = try allocator.dupeZ(u8, zon);
    defer allocator.free(zon_terminated);

    const parsed = std.zon.parse.fromSlice(ZonMirInput, allocator, zon_terminated, null, .{}) catch return error.InvalidZon;
    defer std.zon.parse.free(allocator, parsed);

    return try zonInputToNode(allocator, parsed);
}

/// Convert ZON input structure to parser Mir
///
/// Recursively converts the deserialized ZON structure into
/// the Mir format used by the renderer. Handles content
/// duplication and child node creation.
///
/// Parameters:
///   - allocator: Memory allocator
///   - input: Deserialized ZON structure
///
/// Returns: Converted Mir structure
fn zonInputToNode(allocator: std.mem.Allocator, input: ZonMirInput) !Mir {
    // Get node type directly from enum
    const node_type = input.type;

    var node = Mir.init(allocator, node_type);

    // Set content if present
    if (input.content) |content| {
        node.content = try allocator.dupe(u8, content);
    }

    // Set level if present
    node.level = input.level;

    // Convert children
    for (input.children) |child_input| {
        const child_node = try allocator.create(Mir);
        child_node.* = try zonInputToNode(allocator, child_input);
        try node.children.append(child_node);
    }

    return node;
}


test "render empty document" {
    const allocator = std.testing.allocator;

    var root = Mir.init(allocator, .document);
    defer root.deinit(allocator);

    const html = try renderToHtml(allocator, &root);
    defer allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "<!DOCTYPE html>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<body>") != null);
}

test "render heading" {
    const allocator = std.testing.allocator;

    var root = Mir.init(allocator, .document);
    defer root.deinit(allocator);

    const heading = try allocator.create(Mir);
    heading.* = Mir.init(allocator, .heading);
    heading.level = 2;
    heading.content = try allocator.dupe(u8, "Test Header");

    try root.children.append(heading);

    const html = try renderToHtml(allocator, &root);
    defer allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "<h2>Test Header</h2>") != null);
}

test "render paragraph with inline formatting" {
    const allocator = std.testing.allocator;

    var root = Mir.init(allocator, .document);
    defer root.deinit(allocator);

    const para = try allocator.create(Mir);
    para.* = Mir.init(allocator, .paragraph);

    const text1 = try allocator.create(Mir);
    text1.* = Mir.init(allocator, .text);
    text1.content = try allocator.dupe(u8, "This is ");

    const bold = try allocator.create(Mir);
    bold.* = Mir.init(allocator, .strong);
    bold.content = try allocator.dupe(u8, "bold");

    const text2 = try allocator.create(Mir);
    text2.* = Mir.init(allocator, .text);
    text2.content = try allocator.dupe(u8, " text.");

    try para.children.append(text1);
    try para.children.append(bold);
    try para.children.append(text2);
    try root.children.append(para);

    const html = try renderToHtml(allocator, &root);
    defer allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "<p>This is <strong>bold</strong> text.</p>") != null);
}

test "zonMirToHtml integration" {
    const allocator = std.testing.allocator;

    const zon_mir =
        \\.{
        \\    .type = .document,
        \\    .children = .{
        \\        .{ .type = .heading, .level = 1, .content = "Hello", .children = .{} },
        \\        .{
        \\            .type = .paragraph,
        \\            .content = null,
        \\            .level = null,
        \\            .children = .{
        \\                .{ .type = .text, .content = "This is ", .level = null, .children = .{} },
        \\                .{ .type = .strong, .content = "bold", .level = null, .children = .{} },
        \\                .{ .type = .text, .content = " text.", .level = null, .children = .{} },
        \\            },
        \\        },
        \\    },
        \\    .content = null,
        \\    .level = null,
        \\}
    ;

    const html = try zonMirToHtml(allocator, zon_mir);
    defer allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "<h1>Hello</h1>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<p>This is <strong>bold</strong> text.</p>") != null);
}

test "code block rendering with ZON" {
    const allocator = std.testing.allocator;

    // Test ZON MIR that represents a code block (fenced with ```)
    const zon_mir =
        \\.{
        \\    .type = .document,
        \\    .children = .{
        \\        .{
        \\            .type = .code_block,
        \\            .content = "const std = @import(\"std\");\nconst markdown_parzer = @import(\"markdown_parzer\");",
        \\            .level = null,
        \\            .children = .{},
        \\        },
        \\    },
        \\    .content = null,
        \\    .level = null,
        \\}
    ;

    const html = try zonMirToHtml(allocator, zon_mir);
    defer allocator.free(html);

    // Should contain proper code block
    try std.testing.expect(std.mem.indexOf(u8, html, "<pre><code>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "const std = @import(\"std\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "</code></pre>") != null);

    // Should NOT contain broken code like <code></code>`
    try std.testing.expect(std.mem.indexOf(u8, html, "<code></code>`") == null);
}

