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
        
        // TODO: Implement actual parsing logic
        // This is just a stub for now
        
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