//! Recursive descent parser for Markdown documents
//!
//! This module converts a stream of tokens from the lexer into an
//! Abstract Syntax Tree (AST) representing the document structure.
//! The parser handles all major Markdown elements including headings,
//! paragraphs, lists, code blocks, and inline formatting.
//!
//! ## Features
//! - Complete Markdown element support (headings, lists, code blocks, etc.)
//! - Nested inline formatting (e.g., **`bold code`**)
//! - Robust error handling with fallback to literal text
//! - Memory-safe with proper cleanup via deinit
//! - Loop prevention for malformed input
//!
//! ## Architecture
//! The parser uses a recursive descent approach with separate functions
//! for block-level and inline elements. This separation prevents infinite
//! recursion and provides clean parsing logic.
//!
//! ## Usage
//! ```zig
//! var parser = Parser.init(allocator, tokens);
//! const ast = try parser.parse();
//! defer {
//!     ast.deinit(allocator);
//!     allocator.destroy(ast);
//! }
//! ```

const std = @import("std");
const lexer = @import("lexer.zig");

const Token = lexer.Token;
const TokenType = lexer.TokenType;

/// Node types representing all Markdown elements in the AST
///
/// The NodeType enum defines all possible node types that can appear
/// in the parsed AST. Some types are fully implemented while others
/// are defined for future extension.
///
/// Fully implemented:
/// - document, heading, paragraph, text
/// - emphasis, strong, code, code_block
/// - list, list_item
///
/// Defined but not yet implemented:
/// - link, image, blockquote, horizontal_rule
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

/// AST node representing a Markdown element
///
/// Nodes form a tree structure where each node can have:
/// - A type identifying what Markdown element it represents
/// - Optional content for leaf nodes (text, code)
/// - Optional metadata (e.g., heading level)
/// - Child nodes for container elements
///
/// Memory management:
/// - Nodes own their content and children
/// - Call deinit() to recursively free all resources
/// - Parent nodes are responsible for destroying child nodes
pub const Node = struct {
    /// The type of Markdown element this node represents
    type: NodeType,
    /// Text content for leaf nodes (text, code, code_block)
    content: ?[]const u8 = null,
    /// Heading level (1-6) for heading nodes
    level: ?u8 = null,
    /// Child nodes for container elements
    children: std.ArrayList(*Node),

    /// Initialize a new node with the given type
    ///
    /// Creates a node with an empty children list. Content and level
    /// should be set separately as needed.
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for the children list
    ///   - node_type: The type of Markdown element
    ///
    /// Returns: An initialized Node struct
    pub fn init(allocator: std.mem.Allocator, node_type: NodeType) Node {
        return Node{
            .type = node_type,
            .children = std.ArrayList(*Node).init(allocator),
        };
    }

    /// Recursively free all resources owned by this node
    ///
    /// Frees:
    /// - The content string (if present)
    /// - All child nodes (recursively)
    /// - The children ArrayList
    ///
    /// Note: Does NOT free the node itself - caller must use
    /// allocator.destroy() for that.
    ///
    /// Parameters:
    ///   - allocator: The allocator used to create this node's resources
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

/// Markdown parser that converts tokens to an AST
///
/// The Parser maintains state while traversing the token stream,
/// building up a hierarchical AST representing the document structure.
///
/// ## Parsing Strategy
/// - Block-level elements are parsed first (headings, paragraphs, lists)
/// - Inline elements are parsed within blocks (emphasis, code, text)
/// - Special parseInlineSimple() prevents recursion in nested formatting
/// - Unknown tokens are safely skipped to prevent infinite loops
pub const Parser = struct {
    /// The token stream to parse (not owned by parser)
    tokens: []const Token,
    /// Current position in the token stream
    current: usize = 0,
    /// Memory allocator for creating nodes
    allocator: std.mem.Allocator,

    /// Initialize a new parser with the given tokens
    ///
    /// The parser does not take ownership of the token slice.
    /// The caller must ensure tokens remain valid during parsing.
    ///
    /// Parameters:
    ///   - allocator: Allocator for creating AST nodes
    ///   - tokens: Token stream from the lexer
    ///
    /// Returns: A new parser ready to parse
    pub fn init(allocator: std.mem.Allocator, tokens: []const Token) Parser {
        return Parser{
            .allocator = allocator,
            .tokens = tokens,
        };
    }

    /// Parse the token stream into an AST
    ///
    /// Creates a document root node and parses all block-level
    /// elements. The returned AST must be freed by the caller.
    ///
    /// Returns: Root node of the AST (type = .document)
    ///
    /// Error: Returns error.OutOfMemory if allocation fails
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

    /// Look at the current token without consuming it
    ///
    /// Used for lookahead operations to determine parsing strategy.
    ///
    /// Returns: Current token, or null if at end of stream
    fn peek(self: *Parser) ?Token {
        if (self.current >= self.tokens.len) return null;
        return self.tokens[self.current];
    }

    /// Consume and return the current token
    ///
    /// Advances the parser position by one token.
    ///
    /// Returns: The consumed token, or null if at end of stream
    fn advance(self: *Parser) ?Token {
        if (self.current >= self.tokens.len) return null;
        const token = self.tokens[self.current];
        self.current += 1;
        return token;
    }

    /// Parse a block-level element
    ///
    /// Identifies and dispatches to the appropriate parser based on
    /// the current token. Handles:
    /// - Headings (#, ##, ###)
    /// - Code blocks (```)
    /// - Lists (-, *)
    /// - Paragraphs (default)
    ///
    /// Returns: Parsed block node, or null if no block found
    fn parseBlock(self: *Parser) !?*Node {
        // Skip whitespace and newlines at block level
        self.skipWhitespaceAndNewlines();

        const token = self.peek() orelse return null;

        switch (token.type) {
            .hash => return try self.parseHeading(),
            .backtick => {
                // Check if this is a fenced code block (```)
                if (self.isCodeBlock()) {
                    return try self.parseCodeBlock();
                } else {
                    return try self.parseParagraph();
                }
            },
            .minus, .star => {
                // Check if this is a list item (- or * followed by space)
                if (self.isListItem()) {
                    return try self.parseList();
                } else {
                    return try self.parseParagraph();
                }
            },
            .eof => return null,
            else => return try self.parseParagraph(),
        }
    }

    /// Parse a heading element
    ///
    /// Counts the number of # symbols to determine heading level,
    /// then parses the heading content as inline elements.
    ///
    /// Handles:
    /// - Multiple heading levels (1-6)
    /// - Optional space after #
    /// - Inline formatting in heading text
    ///
    /// Returns: Heading node with level and children
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

    /// Parse a paragraph element
    ///
    /// Collects inline elements until reaching:
    /// - Double newline (end of paragraph)
    /// - Start of new block element
    /// - End of file
    ///
    /// Smart paragraph termination detects headings and lists
    /// to properly separate block elements.
    ///
    /// Returns: Paragraph node with inline children
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

                // If we hit another newline, EOF, heading, or list item, end paragraph
                if (self.peek()) |next_token| {
                    if (next_token.type == .newline or next_token.type == .eof or next_token.type == .hash) {
                        break;
                    }
                    // Check for list item (- or * followed by space)
                    if ((next_token.type == .minus or next_token.type == .star) and self.isListItem()) {
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

    /// Parse inline elements within blocks
    ///
    /// Main dispatcher for inline formatting. Handles:
    /// - Emphasis (*text*)
    /// - Strong (**text**)
    /// - Inline code (`code`)
    /// - Plain text
    /// - Special characters as literal text
    ///
    /// Returns: Inline node, or null if no inline element found
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

    /// Parse emphasis (*) or strong (**) formatting
    ///
    /// Counts asterisks and looks ahead for matching closing asterisks.
    /// Falls back to literal text if no closing asterisks found.
    ///
    /// Algorithm:
    /// 1. Count opening asterisks
    /// 2. Look ahead for matching closing asterisks
    /// 3. Parse content between as inline elements
    /// 4. Use parseInlineSimple() to prevent recursion
    ///
    /// Returns: Emphasis/strong node, or text node if unmatched
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

        // Look ahead to find closing asterisks
        var found_closing = false;
        var temp_pos = self.current;
        var content_end_pos: usize = 0;

        while (temp_pos < self.tokens.len) {
            const token = self.tokens[temp_pos];
            if (token.type == .star) {
                // Check if we have matching closing asterisks
                var closing_count: u8 = 0;
                var check_pos = temp_pos;
                
                while (check_pos < self.tokens.len and closing_count < star_count) {
                    const closing_token = self.tokens[check_pos];
                    if (closing_token.type == .star) {
                        closing_count += 1;
                        check_pos += 1;
                    } else {
                        break;
                    }
                }

                if (closing_count == star_count) {
                    found_closing = true;
                    content_end_pos = temp_pos;
                    break;
                }
            } else if (token.type == .newline or token.type == .eof) {
                break;
            }
            temp_pos += 1;
        }

        if (!found_closing) {
            // No matching closing, treat as literal text
            self.current = start_pos;
            return try self.parseText();
        }

        // Create emphasis or strong node and parse children
        const node_type: NodeType = if (star_count >= 2) .strong else .emphasis;
        const node = try self.allocator.create(Node);
        node.* = Node.init(self.allocator, node_type);

        // Parse content between asterisks as inline elements (excluding emphasis/strong to avoid recursion)
        while (self.current < content_end_pos) {
            if (try self.parseInlineSimple()) |inline_node| {
                try node.children.append(inline_node);
            } else {
                // If parseInlineSimple returns null, advance to avoid infinite loop
                _ = self.advance();
            }
        }

        // Consume closing asterisks
        for (0..star_count) |_| {
            _ = self.advance();
        }

        return node;
    }

    /// Parse inline elements without emphasis/strong
    ///
    /// Special version of parseInline() that excludes emphasis and
    /// strong to prevent infinite recursion when parsing nested
    /// formatting like **`code`**.
    ///
    /// Returns: Inline node (text or code only)
    fn parseInlineSimple(self: *Parser) !?*Node {
        const token = self.peek() orelse return null;

        switch (token.type) {
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

    /// Parse emphasis with underscores (_text_)
    ///
    /// Currently treats underscores as literal text.
    /// Full implementation reserved for future enhancement.
    ///
    /// Returns: Text node with underscore
    fn parseEmphasisUnderscore(self: *Parser) !?*Node {
        // Similar logic to asterisks but for underscores
        // For now, just treat as text to keep implementation simple
        return try self.parseText();
    }

    /// Parse inline code spans
    ///
    /// Looks for matching backticks and captures content between.
    /// Falls back to literal backtick if no closing found.
    ///
    /// Handles:
    /// - Single backtick delimiters
    /// - Proper content extraction
    /// - Unmatched backticks as literal text
    ///
    /// Returns: Code node with content, or text node if unmatched
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

    /// Parse a text token
    ///
    /// Consumes the current token and creates a text node.
    ///
    /// Returns: Text node with token value as content
    fn parseText(self: *Parser) !?*Node {
        const token = self.advance() orelse return null;
        return try self.parseTextToken(token);
    }

    /// Create a text node from a specific token
    ///
    /// Helper function to create text nodes from any token.
    /// Duplicates the token value for the node to own.
    ///
    /// Parameters:
    ///   - token: Token to convert to text node
    ///
    /// Returns: Text node with duplicated content
    fn parseTextToken(self: *Parser, token: Token) !*Node {
        const text = try self.allocator.create(Node);
        text.* = Node.init(self.allocator, .text);
        text.content = try self.allocator.dupe(u8, token.value);
        return text;
    }

    /// Create a text node with literal content
    ///
    /// Helper for creating text nodes with specific content.
    /// Duplicates the content for the node to own.
    ///
    /// Parameters:
    ///   - content: Text content for the node
    ///
    /// Returns: Text node with duplicated content
    fn parseTextLiteral(self: *Parser, content: []const u8) !*Node {
        const text = try self.allocator.create(Node);
        text.* = Node.init(self.allocator, .text);
        text.content = try self.allocator.dupe(u8, content);
        return text;
    }

    /// Create a text node containing whitespace
    ///
    /// Used to convert newlines to spaces in inline context.
    ///
    /// Parameters:
    ///   - space: Whitespace content (usually " ")
    ///
    /// Returns: Text node with space content
    fn parseSpace(self: *Parser, space: []const u8) !*Node {
        const text = try self.allocator.create(Node);
        text.* = Node.init(self.allocator, .text);
        text.content = try self.allocator.dupe(u8, space);
        return text;
    }

    /// Skip whitespace and newline tokens
    ///
    /// Used at block level to ignore formatting whitespace.
    /// Does not skip whitespace within inline content.
    fn skipWhitespaceAndNewlines(self: *Parser) void {
        while (self.peek()) |token| {
            if (token.type == .space or token.type == .tab or token.type == .newline) {
                _ = self.advance();
            } else {
                break;
            }
        }
    }

    /// Check if current position starts a fenced code block
    ///
    /// Looks ahead to check for three or more consecutive backticks,
    /// which indicates a fenced code block rather than inline code.
    ///
    /// Returns: true if three or more backticks found
    fn isCodeBlock(self: *Parser) bool {
        var temp_pos = self.current;
        var backtick_count: u8 = 0;
        
        // Count consecutive backticks
        while (temp_pos < self.tokens.len) {
            const token = self.tokens[temp_pos];
            if (token.type == .backtick) {
                backtick_count += 1;
                temp_pos += 1;
            } else {
                break;
            }
        }
        
        return backtick_count >= 3;
    }

    /// Parse a fenced code block
    ///
    /// Handles:
    /// - Opening/closing fence detection (``` or more)
    /// - Optional language identifier after opening fence
    /// - Multi-line code content
    /// - Proper fence matching (closing must match opening length)
    ///
    /// Returns: Code block node with content
    fn parseCodeBlock(self: *Parser) !*Node {
        // Count opening backticks
        var opening_count: u8 = 0;
        while (self.peek()) |token| {
            if (token.type == .backtick) {
                opening_count += 1;
                _ = self.advance();
            } else {
                break;
            }
        }
        
        // Skip language identifier if present (e.g., "zig" in ```zig)
        while (self.peek()) |token| {
            if (token.type == .newline) {
                _ = self.advance(); // consume newline
                break;
            } else if (token.type == .eof) {
                break;
            } else {
                _ = self.advance(); // skip language identifier
            }
        }
        
        // Collect content until closing backticks
        var content = std.ArrayList(u8).init(self.allocator);
        defer content.deinit();
        
        while (self.peek()) |token| {
            if (token.type == .backtick) {
                // Check if this is the closing fence
                var temp_pos = self.current;
                var closing_count: u8 = 0;
                
                while (temp_pos < self.tokens.len) {
                    const closing_token = self.tokens[temp_pos];
                    if (closing_token.type == .backtick) {
                        closing_count += 1;
                        temp_pos += 1;
                    } else {
                        break;
                    }
                }
                
                if (closing_count >= opening_count) {
                    // Found closing fence, consume it and break
                    for (0..closing_count) |_| {
                        _ = self.advance();
                    }
                    break;
                } else {
                    // Not enough backticks, treat as content
                    _ = self.advance();
                    try content.appendSlice(token.value);
                }
            } else if (token.type == .eof) {
                break;
            } else {
                _ = self.advance();
                try content.appendSlice(token.value);
            }
        }
        
        const code_block = try self.allocator.create(Node);
        code_block.* = Node.init(self.allocator, .code_block);
        code_block.content = try content.toOwnedSlice();
        
        return code_block;
    }

    /// Check if current position starts a list item
    ///
    /// List items must have:
    /// - Marker (- or *)
    /// - Space after marker
    ///
    /// Returns: true if valid list item pattern found
    fn isListItem(self: *Parser) bool {
        if (self.current >= self.tokens.len) return false;
        
        const first_token = self.tokens[self.current];
        if (first_token.type != .minus and first_token.type != .star) {
            return false;
        }
        
        // Check if followed by space
        if (self.current + 1 >= self.tokens.len) return false;
        const second_token = self.tokens[self.current + 1];
        return second_token.type == .space;
    }

    /// Calculate indentation level for list nesting
    ///
    /// Counts spaces and tabs from start of line to determine
    /// nesting level. Tabs count as 4 spaces.
    ///
    /// Used to handle nested lists based on indentation.
    ///
    /// Returns: Indentation level in spaces
    fn getListIndentLevel(self: *Parser) u32 {
        var temp_pos = self.current;
        var indent_level: u32 = 0;
        
        // Look backwards from current position to find start of line
        while (temp_pos > 0) {
            temp_pos -= 1;
            const token = self.tokens[temp_pos];
            if (token.type == .newline) {
                temp_pos += 1; // Move to first token after newline
                break;
            }
        }
        
        // Count spaces and tabs from start of line
        while (temp_pos < self.current) {
            const token = self.tokens[temp_pos];
            if (token.type == .space) {
                indent_level += 1;
            } else if (token.type == .tab) {
                indent_level += 4; // Treat tab as 4 spaces
            } else {
                break;
            }
            temp_pos += 1;
        }
        
        return indent_level;
    }

    /// Parse a list element
    ///
    /// Entry point for list parsing. Delegates to parseListAtLevel()
    /// with base indentation of 0.
    ///
    /// Returns: List node containing list items
    fn parseList(self: *Parser) !*Node {
        return try self.parseListAtLevel(0);
    }

    /// Parse a list at a specific indentation level
    ///
    /// Handles nested lists by tracking indentation levels.
    /// Items at the same level are siblings, more indented items
    /// create nested lists.
    ///
    /// Parameters:
    ///   - base_indent: Expected indentation for items at this level
    ///
    /// Returns: List node with items at this level
    fn parseListAtLevel(self: *Parser, base_indent: u32) std.mem.Allocator.Error!*Node {
        const list = try self.allocator.create(Node);
        list.* = Node.init(self.allocator, .list);
        
        // Parse consecutive list items at this indentation level
        while (self.peek()) |token| {
            if ((token.type == .minus or token.type == .star) and self.isListItem()) {
                const current_indent = self.getListIndentLevel();
                
                if (current_indent == base_indent) {
                    // Same level - parse this item
                    const list_item = try self.parseListItemWithNesting(base_indent);
                    try list.children.append(list_item);
                } else if (current_indent < base_indent) {
                    // Less indented - return to parent level
                    break;
                } else {
                    // More indented - should be handled by parent item's nested list
                    break;
                }
            } else {
                break;
            }
            
            // Skip whitespace/newlines between list items
            self.skipWhitespaceAndNewlines();
        }
        
        return list;
    }

    /// Parse a single list item
    ///
    /// Entry point for list item parsing. Delegates to
    /// parseListItemWithNesting() with base indentation of 0.
    ///
    /// Returns: List item node with content
    fn parseListItem(self: *Parser) !*Node {
        return try self.parseListItemWithNesting(0);
    }

    /// Parse a list item with nested list support
    ///
    /// Handles:
    /// - List marker consumption (- or *)
    /// - Inline content parsing
    /// - Nested list detection based on indentation
    ///
    /// Parameters:
    ///   - base_indent: Indentation level of this item
    ///
    /// Returns: List item node with content and nested lists
    fn parseListItemWithNesting(self: *Parser, base_indent: u32) std.mem.Allocator.Error!*Node {
        // Consume the - or * marker
        _ = self.advance();
        
        // Consume the space after marker
        if (self.peek()) |token| {
            if (token.type == .space) {
                _ = self.advance();
            }
        }
        
        const list_item = try self.allocator.create(Node);
        list_item.* = Node.init(self.allocator, .list_item);
        
        // Parse list item content as inline elements until newline
        while (self.peek()) |token| {
            if (token.type == .newline or token.type == .eof) {
                break;
            }
            
            if (try self.parseInline()) |inline_node| {
                try list_item.children.append(inline_node);
            } else {
                // Skip unknown tokens
                _ = self.advance();
            }
        }
        
        // After parsing the content, check for nested list items
        self.skipWhitespaceAndNewlines();
        
        // Look ahead for nested list items (more indented)
        while (self.peek()) |token| {
            if ((token.type == .minus or token.type == .star) and self.isListItem()) {
                const current_indent = self.getListIndentLevel();
                
                if (current_indent > base_indent) {
                    // This is a nested list - parse it
                    const nested_list = try self.parseListAtLevel(current_indent);
                    try list_item.children.append(nested_list);
                } else {
                    // Same or less indented - belongs to parent
                    break;
                }
            } else {
                break;
            }
        }
        
        return list_item;
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

/// Helper function to tokenize markdown for testing
///
/// Converts raw markdown text to tokens for parser testing.
/// Duplicates token values since they reference the input string.
///
/// Parameters:
///   - allocator: Allocator for tokens and values
///   - markdown: Raw markdown text
///
/// Returns: Owned slice of tokens with duplicated values
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

/// Helper function to validate AST nodes recursively
///
/// Compares actual AST nodes against expected structure for testing.
/// Validates type, content, level, and children recursively.
///
/// Parameters:
///   - actual: The actual AST node to validate
///   - expected: The expected node structure
///   - test_name: Name of test for error reporting
///
/// Error: Test assertion failures
fn validateNode(actual: *const Node, expected: ExpectedNode, test_name: []const u8) !void {
    // Check node type
    const expected_type = std.meta.stringToEnum(NodeType, expected.type) orelse {
        std.debug.print("Test '{s}' failed: Unknown expected node type '{s}'\n", .{ test_name, expected.type });
        return std.testing.expect(false);
    };

    if (actual.type != expected_type) {
        std.debug.print("Test '{s}' failed: Expected node type {s}, got {s}\n", .{ test_name, @tagName(expected_type), @tagName(actual.type) });
    }
    try std.testing.expectEqual(expected_type, actual.type);

    // Check content if specified
    if (expected.content) |expected_content| {
        if (actual.content) |actual_content| {
            if (!std.mem.eql(u8, actual_content, expected_content)) {
                std.debug.print("Test '{s}' failed: Expected content '{s}', got '{s}'\n", .{ test_name, expected_content, actual_content });
            }
            try std.testing.expectEqualStrings(expected_content, actual_content);
        } else {
            std.debug.print("Test '{s}' failed: Expected content '{s}', got null\n", .{ test_name, expected_content });
            try std.testing.expect(false);
        }
    }

    // Check level if specified (for headings)
    if (expected.level) |expected_level| {
        if (actual.level) |actual_level| {
            if (actual_level != expected_level) {
                std.debug.print("Test '{s}' failed: Expected level {d}, got {d}\n", .{ test_name, expected_level, actual_level });
            }
            try std.testing.expectEqual(expected_level, actual_level);
        } else {
            std.debug.print("Test '{s}' failed: Expected level {d}, got null\n", .{ test_name, expected_level });
            try std.testing.expect(false);
        }
    }

    // Check children count
    if (actual.children.items.len != expected.children.len) {
        std.debug.print("Test '{s}' failed: Expected {d} children, got {d}\n", .{ test_name, expected.children.len, actual.children.items.len });
    }
    try std.testing.expectEqual(expected.children.len, actual.children.items.len);

    // Validate children recursively
    for (actual.children.items, 0..) |child, i| {
        try validateNode(child, expected.children[i], test_name);
    }
}

