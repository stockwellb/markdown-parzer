const std = @import("std");
const markdown_parzer = @import("markdown_parzer");

const Token = markdown_parzer.Token;
const TokenType = markdown_parzer.TokenType;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read JSON tokens from stdin
    const stdin = std.io.getStdIn().reader();
    const json_input = try stdin.readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(json_input);

    // Parse JSON tokens (simplified parsing for now)
    const tokens = try parseJsonTokens(allocator, json_input);
    defer {
        for (tokens) |token| {
            if (token.value.len > 0) {
                allocator.free(token.value);
            }
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

    // Output AST as JSON to stdout
    const stdout = std.io.getStdOut().writer();
    try outputAstAsJson(stdout, ast);
}

fn parseJsonTokens(allocator: std.mem.Allocator, json: []const u8) ![]Token {
    // This is a very simplified JSON parser for our token format
    // In a real implementation, you'd use a proper JSON library
    var tokens = std.ArrayList(Token).init(allocator);
    
    var i: usize = 0;
    while (i < json.len) {
        if (json[i] == '{') {
            // Find the end of this token object
            var brace_count: u32 = 1;
            var j = i + 1;
            while (j < json.len and brace_count > 0) {
                if (json[j] == '{') brace_count += 1;
                if (json[j] == '}') brace_count -= 1;
                j += 1;
            }
            
            // Extract token data (very basic parsing)
            const token_json = json[i..j];
            const token = try parseTokenFromJson(allocator, token_json);
            try tokens.append(token);
            
            i = j;
        } else {
            i += 1;
        }
    }
    
    return tokens.toOwnedSlice();
}

fn parseTokenFromJson(allocator: std.mem.Allocator, json: []const u8) !Token {
    // Very basic JSON parsing - extract type and value
    var token_type: TokenType = .text;
    var value: []const u8 = "";
    const line: u32 = 1;
    const column: u32 = 1;
    
    // Find type
    if (std.mem.indexOf(u8, json, "\"type\":\"")) |type_start| {
        const type_value_start = type_start + 8;
        if (std.mem.indexOf(u8, json[type_value_start..], "\"")) |type_end| {
            const type_str = json[type_value_start..type_value_start + type_end];
            token_type = std.meta.stringToEnum(TokenType, type_str) orelse .text;
        }
    }
    
    // Find value
    if (std.mem.indexOf(u8, json, "\"value\":\"")) |value_start| {
        const value_start_idx = value_start + 9;
        if (std.mem.indexOf(u8, json[value_start_idx..], "\"")) |value_end| {
            const raw_value = json[value_start_idx..value_start_idx + value_end];
            value = try unescapeJsonString(allocator, raw_value);
        }
    }
    
    return Token{
        .type = token_type,
        .value = value,
        .line = line,
        .column = column,
    };
}

fn unescapeJsonString(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    if (std.mem.eql(u8, s, "\\n")) {
        const result = try allocator.alloc(u8, 1);
        result[0] = '\n';
        return result;
    }
    if (std.mem.eql(u8, s, "\\t")) {
        const result = try allocator.alloc(u8, 1);
        result[0] = '\t';
        return result;
    }
    if (std.mem.eql(u8, s, "\\\"")) {
        const result = try allocator.alloc(u8, 1);
        result[0] = '"';
        return result;
    }
    if (std.mem.eql(u8, s, "\\\\")) {
        const result = try allocator.alloc(u8, 1);
        result[0] = '\\';
        return result;
    }
    return try allocator.dupe(u8, s);
}

fn outputAstAsJson(writer: anytype, ast: *const markdown_parzer.Node) !void {
    try writer.print("{{", .{});
    try writer.print("\"type\":\"{s}\"", .{@tagName(ast.type)});
    
    if (ast.content) |content| {
        try writer.print(",\"content\":", .{});
        try std.json.stringify(content, .{}, writer);
    }
    
    if (ast.level) |level| {
        try writer.print(",\"level\":{d}", .{level});
    }
    
    if (ast.children.items.len > 0) {
        try writer.print(",\"children\":[", .{});
        for (ast.children.items, 0..) |child, i| {
            if (i > 0) try writer.print(",", .{});
            try outputAstAsJson(writer, child);
        }
        try writer.print("]", .{});
    }
    
    try writer.print("}}", .{});
}

