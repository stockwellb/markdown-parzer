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

    // Convert tokens to HTML
    const html = try tokensToHtml(allocator, tokens);
    defer allocator.free(html);

    // Output HTML to stdout
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{s}", .{html});
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

fn tokensToHtml(allocator: std.mem.Allocator, tokens: []const Token) ![]u8 {
    var html = std.ArrayList(u8).init(allocator);
    var writer = html.writer();
    
    try writer.print("<!DOCTYPE html>\n<html>\n<head>\n<title>Parsed Markdown</title>\n</head>\n<body>\n", .{});
    
    var i: usize = 0;
    var in_heading = false;
    var heading_level: u8 = 1;
    var in_paragraph = false;
    var in_strong = false;
    var strong_count: u8 = 0;
    
    while (i < tokens.len) {
        const token = tokens[i];
        
        switch (token.type) {
            .hash => {
                if (!in_heading) {
                    // Count consecutive hashes for heading level
                    heading_level = 1;
                    var j = i + 1;
                    while (j < tokens.len and tokens[j].type == .hash) {
                        heading_level += 1;
                        j += 1;
                    }
                    try writer.print("<h{d}>", .{heading_level});
                    in_heading = true;
                    i = j - 1; // Skip the counted hashes
                }
            },
            .star => {
                strong_count += 1;
                if (strong_count == 2) {
                    if (in_strong) {
                        try writer.print("</strong>", .{});
                        in_strong = false;
                    } else {
                        try writer.print("<strong>", .{});
                        in_strong = true;
                    }
                    strong_count = 0;
                }
            },
            .newline => {
                if (in_heading) {
                    try writer.print("</h{d}>\n", .{heading_level});
                    in_heading = false;
                } else if (in_paragraph) {
                    try writer.print("</p>\n", .{});
                    in_paragraph = false;
                }
                strong_count = 0; // Reset star count on newline
            },
            .text => {
                if (!in_heading and !in_paragraph) {
                    try writer.print("<p>", .{});
                    in_paragraph = true;
                }
                try writer.print("{s}", .{token.value});
            },
            .space => {
                try writer.print(" ", .{});
            },
            .eof => break,
            else => {
                // Handle other tokens as plain text for now
                try writer.print("{s}", .{token.value});
            },
        }
        i += 1;
    }
    
    // Close any open tags
    if (in_strong) try writer.print("</strong>", .{});
    if (in_heading) try writer.print("</h{d}>\n", .{heading_level});
    if (in_paragraph) try writer.print("</p>\n", .{});
    
    try writer.print("</body>\n</html>\n", .{});
    
    return html.toOwnedSlice();
}