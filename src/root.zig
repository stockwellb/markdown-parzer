//! markdown_parzer library - A Markdown lexer and parser for Zig
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const html = @import("html.zig");

// Re-export lexer types for library users
pub const Token = lexer.Token;
pub const TokenType = lexer.TokenType;
pub const Tokenizer = lexer.Tokenizer;

// Re-export parser types for library users
pub const Node = parser.Node;
pub const NodeType = parser.NodeType;
pub const Parser = parser.Parser;

// Re-export HTML renderer functions for library users
pub const renderToHtml = html.renderToHtml;
pub const renderToHtmlWithTemplate = html.renderToHtmlWithTemplate;
pub const renderToHtmlBody = html.renderToHtmlBody;
pub const renderNode = html.renderNode;
pub const zonAstToHtml = html.zonAstToHtml;
pub const zonAstToHtmlWithTemplate = html.zonAstToHtmlWithTemplate;
pub const zonAstToHtmlBody = html.zonAstToHtmlBody;
pub const jsonAstToHtml = html.jsonAstToHtml; // Legacy support
pub const default_html_template = html.default_html_template;

/// Tokenize a markdown string and return all tokens
pub fn tokenize(allocator: std.mem.Allocator, input: []const u8) ![]Token {
    var tokens = std.ArrayList(Token).init(allocator);
    defer tokens.deinit();

    var tokenizer = Tokenizer.init(input);
    
    while (true) {
        const token = tokenizer.next();
        try tokens.append(token);
        if (token.type == .eof) break;
    }
    
    return tokens.toOwnedSlice();
}

/// Print tokens in a human-readable format
pub fn printTokens(writer: anytype, tokens: []const Token) !void {
    for (tokens) |token| {
        if (token.type == .newline) {
            try writer.print("Line {d:>3}, Col {d:>3}: {s} = \"\\n\"\n", .{ token.line, token.column, @tagName(token.type) });
        } else if (token.type == .tab) {
            try writer.print("Line {d:>3}, Col {d:>3}: {s} = \"\\t\"\n", .{ token.line, token.column, @tagName(token.type) });
        } else if (token.type == .space) {
            try writer.print("Line {d:>3}, Col {d:>3}: {s} = \" \"\n", .{ token.line, token.column, @tagName(token.type) });
        } else {
            try writer.print("Line {d:>3}, Col {d:>3}: {s} = \"{s}\"\n", .{ token.line, token.column, @tagName(token.type), token.value });
        }
    }
}

/// Serialize tokens to ZON format
pub fn tokensToZon(allocator: std.mem.Allocator, tokens: []const Token) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    const writer = &aw.writer;
    
    try std.zon.stringify.serialize(tokens, .{}, writer);
    
    return allocator.dupe(u8, aw.getWritten());
}

// Serializable representation of Node for ZON output
const SerializableNode = struct {
    type: NodeType,
    content: ?[]const u8 = null,
    level: ?u8 = null,
    children: []SerializableNode = &[_]SerializableNode{},
    
    fn fromNode(allocator: std.mem.Allocator, node: *const Node) !SerializableNode {
        var children = std.ArrayList(SerializableNode).init(allocator);
        defer children.deinit();
        
        for (node.children.items) |child| {
            try children.append(try fromNode(allocator, child));
        }
        
        return SerializableNode{
            .type = node.type,
            .content = node.content,
            .level = node.level,
            .children = try children.toOwnedSlice(),
        };
    }
    
    fn deinit(self: *SerializableNode, allocator: std.mem.Allocator) void {
        for (self.children) |*child| {
            child.deinit(allocator);
        }
        if (self.children.len > 0) {
            allocator.free(self.children);
        }
    }
};

/// Serialize AST to ZON format  
pub fn astToZon(allocator: std.mem.Allocator, ast: *const Node) ![]u8 {
    var serializable = try SerializableNode.fromNode(allocator, ast);
    defer serializable.deinit(allocator);
    
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    const writer = &aw.writer;
    
    try std.zon.stringify.serializeArbitraryDepth(serializable, .{}, writer);
    
    return allocator.dupe(u8, aw.getWritten());
}

test "tokenize simple markdown" {
    const allocator = std.testing.allocator;
    const input = "# Hello\n**world**";
    
    const tokens = try tokenize(allocator, input);
    defer allocator.free(tokens);
    
    // Tokens: hash, space, "Hello", newline, star, star, "world", star, star, eof = 10 total
    try std.testing.expectEqual(@as(usize, 10), tokens.len);
    try std.testing.expectEqual(TokenType.hash, tokens[0].type);
    try std.testing.expectEqual(TokenType.space, tokens[1].type);
    try std.testing.expectEqual(TokenType.text, tokens[2].type);
    try std.testing.expectEqualStrings("Hello", tokens[2].value);
}
