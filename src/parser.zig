const std = @import("std");
const lexer = @import("lexer.zig");

const Token = lexer.Token;
const TokenType = lexer.TokenType;

// AST Node types for Markdown elements
pub const NodeType = enum {
    document,
    heading,
    paragraph,
    text,
    emphasis,
    strong,
    code,
    code_block,
    list,
    list_item,
    link,
    image,
    blockquote,
    horizontal_rule,
};

pub const Node = struct {
    type: NodeType,
    content: ?[]const u8 = null,
    level: ?u8 = null, // For headings
    children: std.ArrayList(*Node),
    
    pub fn init(allocator: std.mem.Allocator, node_type: NodeType) Node {
        return Node{
            .type = node_type,
            .children = std.ArrayList(*Node).init(allocator),
        };
    }
    
    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        // Free content if it exists
        if (self.content) |content| {
            allocator.free(content);
        }
        
        // Recursively free children
        for (self.children.items) |child| {
            child.deinit(allocator);
            allocator.destroy(child);
        }
        self.children.deinit();
    }
};

pub const Parser = struct {
    tokens: []const Token,
    current: usize = 0,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, tokens: []const Token) Parser {
        return Parser{
            .allocator = allocator,
            .tokens = tokens,
        };
    }
    
    pub fn parse(self: *Parser) !*Node {
        const root = try self.allocator.create(Node);
        root.* = Node.init(self.allocator, .document);
        
        // Parse document content
        while (self.peek()) |_| {
            if (try self.parseBlock()) |block| {
                try root.children.append(block);
            } else {
                // If parseBlock returns null, we need to advance to avoid infinite loop
                _ = self.advance();
            }
        }
        
        return root;
    }
    
    fn peek(self: *Parser) ?Token {
        if (self.current >= self.tokens.len) return null;
        return self.tokens[self.current];
    }
    
    fn advance(self: *Parser) ?Token {
        if (self.current >= self.tokens.len) return null;
        const token = self.tokens[self.current];
        self.current += 1;
        return token;
    }
    
    /// Parse a block-level element (heading, paragraph, etc.)
    fn parseBlock(self: *Parser) !?*Node {
        // Skip whitespace and newlines at block level
        self.skipWhitespaceAndNewlines();
        
        const token = self.peek() orelse return null;
        
        switch (token.type) {
            .hash => return try self.parseHeading(),
            .eof => return null,
            else => return try self.parseParagraph(),
        }
    }
    
    /// Parse a heading (# ## ###)
    fn parseHeading(self: *Parser) !*Node {
        var level: u8 = 0;
        
        // Count hash symbols
        while (self.peek()) |token| {
            if (token.type == .hash) {
                level += 1;
                _ = self.advance();
            } else {
                break;
            }
        }
        
        // Skip space after hashes
        if (self.peek()) |token| {
            if (token.type == .space) {
                _ = self.advance();
            }
        }
        
        // Create heading node
        const heading = try self.allocator.create(Node);
        heading.* = Node.init(self.allocator, .heading);
        heading.level = level;
        
        // Parse heading content as inline elements
        while (self.peek()) |token| {
            if (token.type == .newline or token.type == .eof) {
                break;
            }
            
            if (try self.parseInline()) |inline_node| {
                try heading.children.append(inline_node);
            } else {
                // If parseInline returns null, we need to advance to avoid infinite loop
                _ = self.advance();
            }
        }
        
        return heading;
    }
    
    /// Parse a paragraph
    fn parseParagraph(self: *Parser) !*Node {
        const paragraph = try self.allocator.create(Node);
        paragraph.* = Node.init(self.allocator, .paragraph);
        
        // Parse paragraph content as inline elements
        while (self.peek()) |token| {
            if (token.type == .newline) {
                // Check if this is end of paragraph (double newline or EOF)
                const saved_pos = self.current;
                _ = self.advance(); // consume newline
                
                // Skip whitespace
                while (self.peek()) |next_token| {
                    if (next_token.type == .space or next_token.type == .tab) {
                        _ = self.advance();
                    } else {
                        break;
                    }
                }
                
                // If we hit another newline or EOF, end paragraph
                if (self.peek()) |next_token| {
                    if (next_token.type == .newline or next_token.type == .eof or next_token.type == .hash) {
                        break;
                    }
                }
                
                // Otherwise, restore position and continue paragraph
                self.current = saved_pos;
                if (try self.parseInline()) |inline_node| {
                    try paragraph.children.append(inline_node);
                } else {
                    // If parseInline returns null, advance to avoid infinite loop
                    _ = self.advance();
                }
            } else if (token.type == .eof) {
                break;
            } else {
                if (try self.parseInline()) |inline_node| {
                    try paragraph.children.append(inline_node);
                } else {
                    // If parseInline returns null, advance to avoid infinite loop
                    _ = self.advance();
                }
            }
        }
        
        return paragraph;
    }
    
    /// Parse inline elements (text, emphasis, strong, etc.)
    fn parseInline(self: *Parser) !?*Node {
        const token = self.peek() orelse return null;
        
        switch (token.type) {
            .star => return try self.parseEmphasisOrStrong(),
            .underscore => return try self.parseEmphasisUnderscore(),
            .backtick => return try self.parseCode(),
            .text, .space, .tab => return try self.parseText(),
            .newline => {
                _ = self.advance();
                return try self.parseSpace(" "); // Convert newline to space in inline context
            },
            else => {
                // Handle other characters as text
                _ = self.advance();
                return try self.parseTextToken(token);
            },
        }
    }
    
    /// Parse emphasis or strong emphasis with asterisks
    fn parseEmphasisOrStrong(self: *Parser) !?*Node {
        const start_pos = self.current;
        var star_count: u8 = 0;
        
        // Count asterisks
        while (self.peek()) |token| {
            if (token.type == .star) {
                star_count += 1;
                _ = self.advance();
            } else {
                break;
            }
        }
        
        // Collect content until closing asterisks (simplified approach)
        var content = std.ArrayList(u8).init(self.allocator);
        defer content.deinit();
        
        var found_closing = false;
        while (self.peek()) |token| {
            if (token.type == .star) {
                // Check if we have matching closing asterisks
                const closing_pos = self.current;
                var closing_count: u8 = 0;
                
                while (self.peek()) |closing_token| {
                    if (closing_token.type == .star and closing_count < star_count) {
                        closing_count += 1;
                        _ = self.advance();
                    } else {
                        break;
                    }
                }
                
                if (closing_count == star_count) {
                    found_closing = true;
                    break;
                } else {
                    // Restore position and add the asterisks as content
                    self.current = closing_pos;
                    _ = self.advance();
                    try content.append('*');
                }
            } else if (token.type == .newline or token.type == .eof) {
                break;
            } else {
                _ = self.advance();
                try content.appendSlice(token.value);
            }
        }
        
        if (!found_closing) {
            // No matching closing, treat as literal text
            self.current = start_pos;
            return try self.parseText();
        }
        
        // Create emphasis or strong node with simple text content
        const node_type: NodeType = if (star_count >= 2) .strong else .emphasis;
        const node = try self.allocator.create(Node);
        node.* = Node.init(self.allocator, node_type);
        node.content = try content.toOwnedSlice();
        
        return node;
    }
    
    /// Parse emphasis with underscores
    fn parseEmphasisUnderscore(self: *Parser) !?*Node {
        // Similar logic to asterisks but for underscores
        // For now, just treat as text to keep implementation simple
        return try self.parseText();
    }
    
    /// Parse inline code
    fn parseCode(self: *Parser) !?*Node {
        const start_pos = self.current;
        _ = self.advance(); // consume opening backtick
        
        // Look for closing backtick
        var found_closing = false;
        var temp_pos = self.current;
        
        while (temp_pos < self.tokens.len) {
            const token = self.tokens[temp_pos];
            if (token.type == .backtick) {
                found_closing = true;
                break;
            } else if (token.type == .eof or token.type == .newline) {
                break;
            }
            temp_pos += 1;
        }
        
        if (!found_closing) {
            // No closing backtick found, restore position and treat as literal text
            self.current = start_pos;
            return try self.parseText();
        }
        
        // Found closing backtick, collect content
        var content = std.ArrayList(u8).init(self.allocator);
        defer content.deinit();
        
        while (self.peek()) |token| {
            if (token.type == .backtick) {
                _ = self.advance(); // consume closing backtick
                break;
            } else {
                _ = self.advance();
                try content.appendSlice(token.value);
            }
        }
        
        const code = try self.allocator.create(Node);
        code.* = Node.init(self.allocator, .code);
        code.content = try content.toOwnedSlice();
        
        return code;
    }
    
    /// Parse regular text
    fn parseText(self: *Parser) !?*Node {
        const token = self.advance() orelse return null;
        return try self.parseTextToken(token);
    }
    
    /// Create a text node from a token
    fn parseTextToken(self: *Parser, token: Token) !*Node {
        const text = try self.allocator.create(Node);
        text.* = Node.init(self.allocator, .text);
        text.content = try self.allocator.dupe(u8, token.value);
        return text;
    }
    
    /// Create a text node with literal content
    fn parseTextLiteral(self: *Parser, content: []const u8) !*Node {
        const text = try self.allocator.create(Node);
        text.* = Node.init(self.allocator, .text);
        text.content = try self.allocator.dupe(u8, content);
        return text;
    }
    
    /// Create a space text node
    fn parseSpace(self: *Parser, space: []const u8) !*Node {
        const text = try self.allocator.create(Node);
        text.* = Node.init(self.allocator, .text);
        text.content = try self.allocator.dupe(u8, space);
        return text;
    }
    
    /// Skip whitespace and newlines
    fn skipWhitespaceAndNewlines(self: *Parser) void {
        while (self.peek()) |token| {
            if (token.type == .space or token.type == .tab or token.type == .newline) {
                _ = self.advance();
            } else {
                break;
            }
        }
    }
};

test "parser initialization" {
    const allocator = std.testing.allocator;
    const tokens = [_]Token{
        Token{ .type = .hash, .value = "#", .line = 1, .column = 1 },
        Token{ .type = .eof, .value = "", .line = 1, .column = 2 },
    };
    
    var parser = Parser.init(allocator, &tokens);
    const ast = try parser.parse();
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }
    
    try std.testing.expectEqual(NodeType.document, ast.type);
}

test "parse simple heading" {
    const allocator = std.testing.allocator;
    const tokens = [_]Token{
        Token{ .type = .hash, .value = "#", .line = 1, .column = 1 },
        Token{ .type = .space, .value = " ", .line = 1, .column = 2 },
        Token{ .type = .text, .value = "Hello", .line = 1, .column = 3 },
        Token{ .type = .eof, .value = "", .line = 1, .column = 8 },
    };
    
    var parser = Parser.init(allocator, &tokens);
    const ast = try parser.parse();
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }
    
    try std.testing.expectEqual(NodeType.document, ast.type);
    try std.testing.expectEqual(@as(usize, 1), ast.children.items.len);
    
    const heading = ast.children.items[0];
    try std.testing.expectEqual(NodeType.heading, heading.type);
    try std.testing.expectEqual(@as(u8, 1), heading.level.?);
}

// Test data structures for comprehensive parser testing
const ParserTestCase = struct {
    name: []const u8,
    markdown: []const u8,
    expected_ast: ExpectedNode,
};

const ExpectedNode = struct {
    type: []const u8,
    content: ?[]const u8 = null,
    level: ?u8 = null,
    children: []const ExpectedNode = &[_]ExpectedNode{},
};

test "comprehensive parser tests" {
    const test_cases = &[_]ParserTestCase{
        // Basic elements
        .{ 
            .name = "simple_text", 
            .markdown = "Hello world",
            .expected_ast = .{
                .type = "document",
                .children = &[_]ExpectedNode{
                    .{
                        .type = "paragraph",
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "Hello" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "world" },
                        },
                    },
                },
            },
        },
        
        // Headings
        .{
            .name = "heading_level_1",
            .markdown = "# Main Title",
            .expected_ast = .{
                .type = "document",
                .children = &[_]ExpectedNode{
                    .{
                        .type = "heading",
                        .level = 1,
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "Main" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "Title" },
                        },
                    },
                },
            },
        },
        
        .{
            .name = "heading_level_3",
            .markdown = "### Subsection",
            .expected_ast = .{
                .type = "document",
                .children = &[_]ExpectedNode{
                    .{
                        .type = "heading",
                        .level = 3,
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "Subsection" },
                        },
                    },
                },
            },
        },
        
        // Emphasis and strong
        .{
            .name = "emphasis",
            .markdown = "This is *italic* text",
            .expected_ast = .{
                .type = "document",
                .children = &[_]ExpectedNode{
                    .{
                        .type = "paragraph",
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "This" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "is" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "emphasis", .content = "italic" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "text" },
                        },
                    },
                },
            },
        },
        
        .{
            .name = "strong",
            .markdown = "This is **bold** text",
            .expected_ast = .{
                .type = "document",
                .children = &[_]ExpectedNode{
                    .{
                        .type = "paragraph",
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "This" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "is" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "strong", .content = "bold" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "text" },
                        },
                    },
                },
            },
        },
        
        // Inline code
        .{
            .name = "inline_code",
            .markdown = "Use `code` here",
            .expected_ast = .{
                .type = "document",
                .children = &[_]ExpectedNode{
                    .{
                        .type = "paragraph",
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "Use" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "code", .content = "code" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "here" },
                        },
                    },
                },
            },
        },
        
        // Multiple paragraphs
        .{
            .name = "multiple_paragraphs",
            .markdown = "First paragraph\n\nSecond paragraph",
            .expected_ast = .{
                .type = "document",
                .children = &[_]ExpectedNode{
                    .{
                        .type = "paragraph",
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "First" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "paragraph" },
                        },
                    },
                    .{
                        .type = "paragraph",
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "Second" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "paragraph" },
                        },
                    },
                },
            },
        },
        
        // Mixed content
        .{
            .name = "mixed_content",
            .markdown = "# Title\n\nThis is **bold** and *italic* with `code`",
            .expected_ast = .{
                .type = "document",
                .children = &[_]ExpectedNode{
                    .{
                        .type = "heading",
                        .level = 1,
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "Title" },
                        },
                    },
                    .{
                        .type = "paragraph",
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "This" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "is" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "strong", .content = "bold" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "and" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "emphasis", .content = "italic" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "with" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "code", .content = "code" },
                        },
                    },
                },
            },
        },
        
        // Edge cases
        .{
            .name = "unmatched_emphasis",
            .markdown = "This is *unmatched emphasis",
            .expected_ast = .{
                .type = "document",
                .children = &[_]ExpectedNode{
                    .{
                        .type = "paragraph",
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "This" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "is" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "*" },
                            .{ .type = "text", .content = "unmatched" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "emphasis" },
                        },
                    },
                },
            },
        },
        
        .{
            .name = "unmatched_code",
            .markdown = "This is `unmatched code",
            .expected_ast = .{
                .type = "document",
                .children = &[_]ExpectedNode{
                    .{
                        .type = "paragraph",
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "This" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "is" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "`" },
                            .{ .type = "text", .content = "unmatched" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "code" },
                        },
                    },
                },
            },
        },
        
        .{
            .name = "empty_emphasis",
            .markdown = "This is ** empty",
            .expected_ast = .{
                .type = "document",
                .children = &[_]ExpectedNode{
                    .{
                        .type = "paragraph",
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "This" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "is" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "*" },
                            .{ .type = "text", .content = "*" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "empty" },
                        },
                    },
                },
            },
        },
        
        .{
            .name = "special_characters",
            .markdown = "Text with - and _ and | characters",
            .expected_ast = .{
                .type = "document",
                .children = &[_]ExpectedNode{
                    .{
                        .type = "paragraph",
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "Text" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "with" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "-" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "and" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "_" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "and" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "|" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "characters" },
                        },
                    },
                },
            },
        },
        
        // Complex stress tests
        .{
            .name = "nested_emphasis_in_heading",
            .markdown = "# This is **bold** in heading",
            .expected_ast = .{
                .type = "document",
                .children = &[_]ExpectedNode{
                    .{
                        .type = "heading",
                        .level = 1,
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "This" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "is" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "strong", .content = "bold" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "in" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "heading" },
                        },
                    },
                },
            },
        },
        
        .{
            .name = "multiple_emphasis_types",
            .markdown = "Mix of **bold**, *italic*, and `code` together",
            .expected_ast = .{
                .type = "document",
                .children = &[_]ExpectedNode{
                    .{
                        .type = "paragraph",
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "Mix" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "of" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "strong", .content = "bold" },
                            .{ .type = "text", .content = "," },
                            .{ .type = "text", .content = " " },
                            .{ .type = "emphasis", .content = "italic" },
                            .{ .type = "text", .content = "," },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "and" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "code", .content = "code" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "together" },
                        },
                    },
                },
            },
        },
        
        .{
            .name = "consecutive_emphasis",
            .markdown = "**bold***italic*",
            .expected_ast = .{
                .type = "document",
                .children = &[_]ExpectedNode{
                    .{
                        .type = "paragraph",
                        .children = &[_]ExpectedNode{
                            .{ .type = "strong", .content = "bold" },
                            .{ .type = "emphasis", .content = "italic" },
                        },
                    },
                },
            },
        },
        
        .{
            .name = "empty_document",
            .markdown = "",
            .expected_ast = .{
                .type = "document",
                .children = &[_]ExpectedNode{},
            },
        },
        
        .{
            .name = "only_whitespace",
            .markdown = "   \n\n  \t  ",
            .expected_ast = .{
                .type = "document",
                .children = &[_]ExpectedNode{},
            },
        },
        
        .{
            .name = "heading_without_space",
            .markdown = "#NoSpace",
            .expected_ast = .{
                .type = "document",
                .children = &[_]ExpectedNode{
                    .{
                        .type = "heading",
                        .level = 1,
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "NoSpace" },
                        },
                    },
                },
            },
        },
        
        .{
            .name = "complex_document",
            .markdown = "# Main Title\n\nThis is a paragraph with **bold** text.\n\n## Subsection\n\nAnother paragraph with `code` and *emphasis*.\n\n### Deep heading\n\nFinal paragraph.",
            .expected_ast = .{
                .type = "document",
                .children = &[_]ExpectedNode{
                    .{
                        .type = "heading",
                        .level = 1,
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "Main" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "Title" },
                        },
                    },
                    .{
                        .type = "paragraph",
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "This" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "is" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "a" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "paragraph" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "with" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "strong", .content = "bold" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "text" },
                            .{ .type = "text", .content = "." },
                        },
                    },
                    .{
                        .type = "heading",
                        .level = 2,
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "Subsection" },
                        },
                    },
                    .{
                        .type = "paragraph",
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "Another" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "paragraph" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "with" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "code", .content = "code" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "and" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "emphasis", .content = "emphasis" },
                            .{ .type = "text", .content = "." },
                        },
                    },
                    .{
                        .type = "heading",
                        .level = 3,
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "Deep" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "heading" },
                        },
                    },
                    .{
                        .type = "paragraph",
                        .children = &[_]ExpectedNode{
                            .{ .type = "text", .content = "Final" },
                            .{ .type = "text", .content = " " },
                            .{ .type = "text", .content = "paragraph" },
                            .{ .type = "text", .content = "." },
                        },
                    },
                },
            },
        },
    };
    
    // Run tests for each case
    for (test_cases) |test_case| {
        // Tokenize the markdown first
        const tokens = try tokenizeMarkdown(std.testing.allocator, test_case.markdown);
        defer {
            for (tokens) |token| {
                if (token.value.len > 0) {
                    std.testing.allocator.free(token.value);
                }
            }
            std.testing.allocator.free(tokens);
        }
        
        // Parse the tokens
        var parser = Parser.init(std.testing.allocator, tokens);
        const ast = try parser.parse();
        defer {
            ast.deinit(std.testing.allocator);
            std.testing.allocator.destroy(ast);
        }
        
        // Validate the AST structure
        try validateNode(ast, test_case.expected_ast, test_case.name);
    }
}

// Helper function to tokenize markdown for testing
fn tokenizeMarkdown(allocator: std.mem.Allocator, markdown: []const u8) ![]Token {
    const tokenizer_mod = @import("lexer.zig");
    var tokenizer = tokenizer_mod.Tokenizer.init(markdown);
    var tokens = std.ArrayList(Token).init(allocator);
    
    while (true) {
        const token = tokenizer.next();
        // Duplicate the token value since it references the input string
        const owned_value = try allocator.dupe(u8, token.value);
        const owned_token = Token{
            .type = token.type,
            .value = owned_value,
            .line = token.line,
            .column = token.column,
        };
        try tokens.append(owned_token);
        if (token.type == .eof) break;
    }
    
    return tokens.toOwnedSlice();
}

// Helper function to validate AST nodes recursively
fn validateNode(actual: *const Node, expected: ExpectedNode, test_name: []const u8) !void {
    // Check node type
    const expected_type = std.meta.stringToEnum(NodeType, expected.type) orelse {
        std.debug.print("Test '{s}' failed: Unknown expected node type '{s}'\n", .{ test_name, expected.type });
        return std.testing.expect(false);
    };
    
    if (actual.type != expected_type) {
        std.debug.print("Test '{s}' failed: Expected node type {s}, got {s}\n", .{ 
            test_name, @tagName(expected_type), @tagName(actual.type) 
        });
    }
    try std.testing.expectEqual(expected_type, actual.type);
    
    // Check content if specified
    if (expected.content) |expected_content| {
        if (actual.content) |actual_content| {
            if (!std.mem.eql(u8, actual_content, expected_content)) {
                std.debug.print("Test '{s}' failed: Expected content '{s}', got '{s}'\n", .{ 
                    test_name, expected_content, actual_content 
                });
            }
            try std.testing.expectEqualStrings(expected_content, actual_content);
        } else {
            std.debug.print("Test '{s}' failed: Expected content '{s}', got null\n", .{ 
                test_name, expected_content 
            });
            try std.testing.expect(false);
        }
    }
    
    // Check level if specified (for headings)
    if (expected.level) |expected_level| {
        if (actual.level) |actual_level| {
            if (actual_level != expected_level) {
                std.debug.print("Test '{s}' failed: Expected level {d}, got {d}\n", .{ 
                    test_name, expected_level, actual_level 
                });
            }
            try std.testing.expectEqual(expected_level, actual_level);
        } else {
            std.debug.print("Test '{s}' failed: Expected level {d}, got null\n", .{ 
                test_name, expected_level 
            });
            try std.testing.expect(false);
        }
    }
    
    // Check children count
    if (actual.children.items.len != expected.children.len) {
        std.debug.print("Test '{s}' failed: Expected {d} children, got {d}\n", .{ 
            test_name, expected.children.len, actual.children.items.len 
        });
    }
    try std.testing.expectEqual(expected.children.len, actual.children.items.len);
    
    // Validate children recursively
    for (actual.children.items, 0..) |child, i| {
        try validateNode(child, expected.children[i], test_name);
    }
}