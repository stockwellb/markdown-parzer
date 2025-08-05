const std = @import("std");
const markdown_parzer = @import("markdown_parzer");

const Token = markdown_parzer.Token;
const TokenType = markdown_parzer.TokenType;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read ZON tokens from stdin
    const zon_input = try std.fs.File.stdin().readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(zon_input);

    // Parse ZON tokens directly
    const tokens = try parseZonTokens(allocator, zon_input);
    defer {
        for (tokens) |token| {
            allocator.free(token.value);
        }
        allocator.free(tokens);
    }

    // Parse tokens into AST
    var parser = markdown_parzer.Parser.init(allocator, tokens);
    const ast = try parser.parse();
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    // Output AST as ZON to stdout
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();
    const writer = output.writer();
    try outputAstAsZon(writer, ast);
    
    try std.fs.File.stdout().writeAll(output.items);
}

// ZON AST output structure
const AstOutput = struct {
    type: []const u8,
    content: ?[]const u8 = null,
    level: ?u8 = null,
    children: []AstOutput = &[_]AstOutput{},
};

fn parseZonTokens(allocator: std.mem.Allocator, zon: []const u8) ![]Token {
    var tokens = std.ArrayList(Token).init(allocator);
    defer tokens.deinit();
    
    var i: usize = 0;
    
    // Skip to opening .{
    while (i < zon.len and !(zon[i] == '.' and i + 1 < zon.len and zon[i + 1] == '{')) {
        i += 1;
    }
    if (i + 1 >= zon.len) return tokens.toOwnedSlice();
    i += 2; // skip .{
    
    // Parse each token
    while (i < zon.len) {
        // Skip whitespace and commas
        while (i < zon.len and (zon[i] == ' ' or zon[i] == '\t' or zon[i] == '\n' or zon[i] == ',')) {
            i += 1;
        }
        
        if (i >= zon.len or zon[i] == '}') break;
        
        // Look for token start (.{)
        if (zon[i] == '.' and i + 1 < zon.len and zon[i + 1] == '{') {
            const token = try parseZonToken(allocator, zon, &i);
            try tokens.append(token);
        } else {
            i += 1;
        }
    }
    
    return tokens.toOwnedSlice();
}

fn parseZonToken(allocator: std.mem.Allocator, zon: []const u8, pos: *usize) !Token {
    var token_type: TokenType = .text;
    var value: []const u8 = "";
    var line: u32 = 1;
    var column: u32 = 1;
    
    var i = pos.*;
    
    // Skip .{
    if (i + 1 < zon.len and zon[i] == '.' and zon[i + 1] == '{') {
        i += 2;
    }
    
    // Parse each field in the token struct
    while (i < zon.len and zon[i] != '}') {
        // Skip whitespace and commas
        while (i < zon.len and (zon[i] == ' ' or zon[i] == '\t' or zon[i] == '\n' or zon[i] == ',')) {
            i += 1;
        }
        
        if (i >= zon.len or zon[i] == '}') break;
        
        // Check for field names
        if (std.mem.startsWith(u8, zon[i..], ".type =")) {
            i += 7; // skip ".type ="
            token_type = try parseZonString(zon, &i, TokenType);
        } else if (std.mem.startsWith(u8, zon[i..], ".value =")) {
            i += 8; // skip ".value ="
            value = try parseZonStringValue(allocator, zon, &i);
        } else if (std.mem.startsWith(u8, zon[i..], ".line =")) {
            i += 7; // skip ".line ="
            line = try parseZonNumber(zon, &i);
        } else if (std.mem.startsWith(u8, zon[i..], ".column =")) {
            i += 9; // skip ".column ="
            column = try parseZonNumber(zon, &i);
        } else {
            i += 1;
        }
    }
    
    pos.* = i + 1; // skip closing }
    
    return Token{
        .type = token_type,
        .value = value,
        .line = line,
        .column = column,
    };
}

fn parseZonString(zon: []const u8, pos: *usize, comptime T: type) !T {
    var i = pos.*;
    
    // Skip whitespace and find opening quote
    while (i < zon.len and zon[i] != '"') i += 1;
    if (i >= zon.len) return error.InvalidZon;
    i += 1; // skip opening quote
    
    const start = i;
    
    // Find closing quote
    while (i < zon.len and zon[i] != '"') i += 1;
    if (i >= zon.len) return error.InvalidZon;
    
    const str = zon[start..i];
    i += 1; // skip closing quote
    pos.* = i;
    
    return std.meta.stringToEnum(T, str) orelse @enumFromInt(0);
}

fn parseZonStringValue(allocator: std.mem.Allocator, zon: []const u8, pos: *usize) ![]const u8 {
    var i = pos.*;
    
    // Skip whitespace and find opening quote
    while (i < zon.len and zon[i] != '"') i += 1;
    if (i >= zon.len) return "";
    i += 1; // skip opening quote
    
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    // Parse string with escape sequences
    while (i < zon.len and zon[i] != '"') {
        if (zon[i] == '\\' and i + 1 < zon.len) {
            i += 1;
            switch (zon[i]) {
                'n' => try result.append('\n'),
                't' => try result.append('\t'),
                'r' => try result.append('\r'),
                '\\' => try result.append('\\'),
                '"' => try result.append('"'),
                else => {
                    try result.append('\\');
                    try result.append(zon[i]);
                },
            }
        } else {
            try result.append(zon[i]);
        }
        i += 1;
    }
    
    if (i < zon.len) i += 1; // skip closing quote
    pos.* = i;
    
    return result.toOwnedSlice();
}

fn parseZonNumber(zon: []const u8, pos: *usize) !u32 {
    var i = pos.*;
    
    // Skip whitespace
    while (i < zon.len and (zon[i] == ' ' or zon[i] == '\t')) i += 1;
    
    const start = i;
    while (i < zon.len and zon[i] >= '0' and zon[i] <= '9') i += 1;
    
    pos.* = i;
    
    if (start == i) return 0;
    return try std.fmt.parseInt(u32, zon[start..i], 10);
}

fn outputAstAsZon(writer: anytype, ast: *const markdown_parzer.Node) !void {
    try writer.print(".{{ .type = \"{s}\"", .{@tagName(ast.type)});
    
    if (ast.content) |content| {
        try writer.print(", .content = \"", .{});
        try escapeZonString(content, writer);
        try writer.print("\"", .{});
    }
    
    if (ast.level) |level| {
        try writer.print(", .level = {d}", .{level});
    }
    
    if (ast.children.items.len > 0) {
        try writer.print(", .children = .{{\n", .{});
        for (ast.children.items, 0..) |child, i| {
            if (i > 0) try writer.print(",\n", .{});
            try writer.print("        ", .{});
            try outputAstAsZon(writer, child);
        }
        try writer.print("\n    }}", .{});
    }
    
    try writer.print(" }}", .{});
    if (ast.type == .document) try writer.print("\n", .{});
}

fn escapeZonString(s: []const u8, writer: anytype) !void {
    for (s) |c| {
        switch (c) {
            '"' => try writer.print("\\\"", .{}),
            '\\' => try writer.print("\\\\", .{}),
            '\n' => try writer.print("\\n", .{}),
            '\t' => try writer.print("\\t", .{}),
            '\r' => try writer.print("\\r", .{}),
            else => try writer.writeByte(c),
        }
    }
}

