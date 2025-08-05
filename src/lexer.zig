const std = @import("std");

pub const TokenType = enum {
    // Single character tokens
    hash, // #
    star, // *
    underscore, // _
    backtick, // `
    tilde, // ~
    newline, // \n
    space, // ' '
    tab, // \t
    left_bracket, // [
    right_bracket, // ]
    left_paren, // (
    right_paren, // )
    left_angle, // <
    right_angle, // >
    exclamation, // !
    plus, // +
    minus, // -
    dot, // .
    colon, // :
    semicolon, // ;
    slash, // /
    backslash, // \
    equals, // =
    quote, // "
    single_quote, // '
    question, // ?
    comma, // ,
    pipe, // |
    ampersand, // &
    percent, // %
    at, // @
    dollar, // $
    caret, // ^
    left_brace, // {
    right_brace, // }

    // Multi-character tokens
    digit, // 0-9
    text, // any other text
    
    // Non-printing characters
    zero_width_space, // \u200B
    non_breaking_space, // \u00A0
    unicode_whitespace, // other Unicode whitespace
    control_char, // 0x00-0x1F (except \t, \n, \r)
    byte_order_mark, // \uFEFF
    unknown_nonprinting, // other non-printing chars
    
    eof, // end of file
};

pub const Token = struct {
    type: TokenType,
    value: []const u8,
    line: u32,
    column: u32,
};

pub const Tokenizer = struct {
    input: []const u8,
    position: usize = 0,
    line: u32 = 1,
    column: u32 = 1,

    /// Initialize a new tokenizer with the given input string
    pub fn init(input: []const u8) Tokenizer {
        return Tokenizer{ .input = input };
    }

    /// Get the next token from the input
    /// Returns EOF token when input is exhausted
    pub fn next(self: *Tokenizer) Token {
        // Skip carriage returns only
        self.skipCarriageReturn();

        // Remember where this token starts
        const start_line = self.line;
        const start_column = self.column;
        const start_pos = self.position;

        // Check if we're at EOF
        const maybe_char = self.peek();
        if (maybe_char == null) {
            return Token{
                .type = .eof,
                .value = "",
                .line = start_line,
                .column = start_column,
            };
        }

        const char = maybe_char.?;

        // Skip carriage returns
        if (char == '\r') {
            self.position += 1;  // Skip without updating line/column
            return self.next();  // Recursively get the next real token
        }

        // Check for multi-byte Unicode non-printing characters first
        if (self.tryConsumeUnicodeNonPrinting(start_line, start_column, start_pos)) |token| {
            return token;
        }

        // Check for single-byte non-printing characters
        if (getNonPrintingTokenType(char)) |nonprinting_type| {
            self.advance();
            return self.makeToken(nonprinting_type, start_line, start_column, start_pos);
        }

        // Single character tokens
        // Map characters to token types
        const token_type = getTokenType(char);

        // Handle single character tokens
        if (token_type) |tt| {
            self.advance();
            return self.makeToken(tt, start_line, start_column, start_pos);
        }

        // Collect consecutive text characters
        self.collectText();
        return self.makeToken(.text, start_line, start_column, start_pos);
    }

    /// Try to consume a multi-byte Unicode non-printing character
    /// Returns token if found, null otherwise
    fn tryConsumeUnicodeNonPrinting(self: *Tokenizer, start_line: u32, start_column: u32, start_pos: usize) ?Token {
        if (self.getUnicodeNonPrintingType()) |unicode_type| {
            // Advance by the appropriate number of bytes and update column
            switch (unicode_type) {
                .zero_width_space => {
                    self.position += 3;
                    // Zero-width space takes no visual space, don't increment column
                },
                .byte_order_mark => {
                    self.position += 3;
                    self.column += 1; // BOM is usually invisible but takes logical space
                },
                .non_breaking_space => {
                    self.position += 2;
                    self.column += 1; // Non-breaking space takes one column
                },
                else => self.advance(), // fallback
            }
            return self.makeToken(unicode_type, start_line, start_column, start_pos);
        }
        return null;
    }

    /// Collect consecutive text characters until hitting a special character,
    /// non-printing character, or end of input
    fn collectText(self: *Tokenizer) void {
        while (self.peek()) |c| {
            if (c == '\r') break; // Stop at \r (will be skipped by next() call)
            if (getTokenType(c) != null) break; // Stop at next special character
            if (getNonPrintingTokenType(c) != null) break; // Stop at non-printing chars
            if (self.getUnicodeNonPrintingType() != null) break; // Stop at Unicode non-printing chars 
            self.advance();
        }
    }

    /// Look at the current character without consuming it
    /// Returns null if at end of input
    fn peek(self: *const Tokenizer) ?u8 {
        if (self.position >= self.input.len) return null;
        return self.input[self.position];
    }

    /// Consume the current character and advance position
    /// Updates line and column tracking for error reporting
    fn advance(self: *Tokenizer) void {
        if (self.position < self.input.len) {
            const c = self.input[self.position];
            if (c == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
            self.position += 1;
        }
    }

    /// Skip only carriage returns
    /// Spaces, tabs, and newlines are significant tokens in Markdown
    fn skipCarriageReturn(self: *Tokenizer) void {
        while (self.position < self.input.len and 
               self.input[self.position] == '\r') {
            self.position += 1;  // Just increment position, don't update line/column
        }
    }

    /// Helper to create a token and advance
    fn makeToken(self: *const Tokenizer, token_type: TokenType, start_line: u32, start_column: u32, start_pos: usize) Token {
        return Token{
            .type = token_type,
            .value = self.input[start_pos..self.position],
            .line = start_line,
            .column = start_column,
        };
    }

    /// Check if a character is a non-printing character that should be categorized
    fn getNonPrintingTokenType(c: u8) ?TokenType {
        // Control characters (0x00-0x1F) except tab, newline, carriage return
        if (c < 0x20 and c != '\t' and c != '\n' and c != '\r') {
            return .control_char;
        }
        
        // Non-breaking space (0xA0 in Latin-1, but we're dealing with UTF-8 bytes)
        // This is a simplified check - full Unicode handling would be more complex
        if (c == 0xA0) {
            return .non_breaking_space;
        }
        
        // DEL character (0x7F)
        if (c == 0x7F) {
            return .control_char;
        }
        
        return null;
    }
    
    /// Check if we're looking at a multi-byte Unicode non-printing character
    fn getUnicodeNonPrintingType(self: *const Tokenizer) ?TokenType {
        if (self.position >= self.input.len) return null;
        
        // Zero-width space (U+200B): UTF-8 bytes E2 80 8B
        if (self.position + 2 < self.input.len and
            self.input[self.position] == 0xE2 and
            self.input[self.position + 1] == 0x80 and
            self.input[self.position + 2] == 0x8B) {
            return .zero_width_space;
        }
        
        // Byte order mark (U+FEFF): UTF-8 bytes EF BB BF
        if (self.position + 2 < self.input.len and
            self.input[self.position] == 0xEF and
            self.input[self.position + 1] == 0xBB and
            self.input[self.position + 2] == 0xBF) {
            return .byte_order_mark;
        }
        
        // Non-breaking space (U+00A0): UTF-8 bytes C2 A0
        if (self.position + 1 < self.input.len and
            self.input[self.position] == 0xC2 and
            self.input[self.position + 1] == 0xA0) {
            return .non_breaking_space;
        }
        
        // Could add more Unicode whitespace detection here
        // For now, we'll catch common problematic ones
        
        return null;
    }
    
    fn getTokenType(c: u8) ?TokenType {
        return switch (c) {
            '#' => .hash,
            '*' => .star,
            '_' => .underscore,
            '`' => .backtick,
            '~' => .tilde,
            '\n' => .newline,
            '\r' => null,  // Treat \r as special but return null to skip it
            ' ' => .space,
            '\t' => .tab,
            '[' => .left_bracket,
            ']' => .right_bracket,
            '(' => .left_paren,
            ')' => .right_paren,
            '<' => .left_angle,
            '>' => .right_angle,
            '!' => .exclamation,
            '+' => .plus,
            '-' => .minus,
            '.' => .dot,
            ':' => .colon,
            ';' => .semicolon,
            '/' => .slash,
            '\\' => .backslash,
            '=' => .equals,
            '"' => .quote,
            '\'' => .single_quote,
            '?' => .question,
            ',' => .comma,
            '|' => .pipe,
            '&' => .ampersand,
            '%' => .percent,
            '@' => .at,
            '$' => .dollar,
            '^' => .caret,
            '{' => .left_brace,
            '}' => .right_brace,
            '0'...'9' => .digit, // Digits
            else => null,
        };
    }
};

// Test data structures for .zon parsing
const TestCase = struct {
    name: []const u8,
    input: []const u8,
    expected: []const ExpectedToken,
};

const ExpectedToken = struct {
    type: []const u8,
    value: []const u8,
    line: u32,
    column: u32,
};

const TestData = struct {
    test_cases: []const TestCase,
};

fn stringToTokenType(type_str: []const u8) TokenType {
    return std.meta.stringToEnum(TokenType, type_str) orelse {
        std.debug.panic("Unknown token type: {s}", .{type_str});
    };
}

test "comprehensive lexer tests from .zon data" {
    // TODO: In the future, parse the actual .zon file data
    // const test_data_content = @embedFile("lexer_tests.zon");

    // Parse the .zon data - this is a simplified parser for our specific format
    // In a production system, you'd use a proper .zon parser
    const test_cases = &[_]TestCase{
        .{ .name = "empty_input", .input = "", .expected = &[_]ExpectedToken{
            .{ .type = "eof", .value = "", .line = 1, .column = 1 },
        } },
        .{ .name = "single_hash", .input = "#", .expected = &[_]ExpectedToken{
            .{ .type = "hash", .value = "#", .line = 1, .column = 1 },
            .{ .type = "eof", .value = "", .line = 1, .column = 2 },
        } },
        .{ .name = "simple_heading", .input = "# Hello", .expected = &[_]ExpectedToken{
            .{ .type = "hash", .value = "#", .line = 1, .column = 1 },
            .{ .type = "space", .value = " ", .line = 1, .column = 2 },
            .{ .type = "text", .value = "Hello", .line = 1, .column = 3 },
            .{ .type = "eof", .value = "", .line = 1, .column = 8 },
        } },
        .{ .name = "bold_text", .input = "**bold**", .expected = &[_]ExpectedToken{
            .{ .type = "star", .value = "*", .line = 1, .column = 1 },
            .{ .type = "star", .value = "*", .line = 1, .column = 2 },
            .{ .type = "text", .value = "bold", .line = 1, .column = 3 },
            .{ .type = "star", .value = "*", .line = 1, .column = 7 },
            .{ .type = "star", .value = "*", .line = 1, .column = 8 },
            .{ .type = "eof", .value = "", .line = 1, .column = 9 },
        } },
        .{ .name = "italic_text", .input = "_italic_", .expected = &[_]ExpectedToken{
            .{ .type = "underscore", .value = "_", .line = 1, .column = 1 },
            .{ .type = "text", .value = "italic", .line = 1, .column = 2 },
            .{ .type = "underscore", .value = "_", .line = 1, .column = 8 },
            .{ .type = "eof", .value = "", .line = 1, .column = 9 },
        } },
        .{ .name = "code_inline", .input = "`code`", .expected = &[_]ExpectedToken{
            .{ .type = "backtick", .value = "`", .line = 1, .column = 1 },
            .{ .type = "text", .value = "code", .line = 1, .column = 2 },
            .{ .type = "backtick", .value = "`", .line = 1, .column = 6 },
            .{ .type = "eof", .value = "", .line = 1, .column = 7 },
        } },
        .{ .name = "links", .input = "[text](url)", .expected = &[_]ExpectedToken{
            .{ .type = "left_bracket", .value = "[", .line = 1, .column = 1 },
            .{ .type = "text", .value = "text", .line = 1, .column = 2 },
            .{ .type = "right_bracket", .value = "]", .line = 1, .column = 6 },
            .{ .type = "left_paren", .value = "(", .line = 1, .column = 7 },
            .{ .type = "text", .value = "url", .line = 1, .column = 8 },
            .{ .type = "right_paren", .value = ")", .line = 1, .column = 11 },
            .{ .type = "eof", .value = "", .line = 1, .column = 12 },
        } },
        .{ .name = "lists", .input = "- item\n+ item", .expected = &[_]ExpectedToken{
            .{ .type = "minus", .value = "-", .line = 1, .column = 1 },
            .{ .type = "space", .value = " ", .line = 1, .column = 2 },
            .{ .type = "text", .value = "item", .line = 1, .column = 3 },
            .{ .type = "newline", .value = "\n", .line = 1, .column = 7 },
            .{ .type = "plus", .value = "+", .line = 2, .column = 1 },
            .{ .type = "space", .value = " ", .line = 2, .column = 2 },
            .{ .type = "text", .value = "item", .line = 2, .column = 3 },
            .{ .type = "eof", .value = "", .line = 2, .column = 7 },
        } },
        .{ .name = "mixed_whitespace", .input = " \t\n ", .expected = &[_]ExpectedToken{
            .{ .type = "space", .value = " ", .line = 1, .column = 1 },
            .{ .type = "tab", .value = "\t", .line = 1, .column = 2 },
            .{ .type = "newline", .value = "\n", .line = 1, .column = 3 },
            .{ .type = "space", .value = " ", .line = 2, .column = 1 },
            .{ .type = "eof", .value = "", .line = 2, .column = 2 },
        } },
        .{ .name = "all_special_chars", .input = "#*_`~[]()<>!+-.:;/\\=\"'?,%@$^{}&|", .expected = &[_]ExpectedToken{
            .{ .type = "hash", .value = "#", .line = 1, .column = 1 },
            .{ .type = "star", .value = "*", .line = 1, .column = 2 },
            .{ .type = "underscore", .value = "_", .line = 1, .column = 3 },
            .{ .type = "backtick", .value = "`", .line = 1, .column = 4 },
            .{ .type = "tilde", .value = "~", .line = 1, .column = 5 },
            .{ .type = "left_bracket", .value = "[", .line = 1, .column = 6 },
            .{ .type = "right_bracket", .value = "]", .line = 1, .column = 7 },
            .{ .type = "left_paren", .value = "(", .line = 1, .column = 8 },
            .{ .type = "right_paren", .value = ")", .line = 1, .column = 9 },
            .{ .type = "left_angle", .value = "<", .line = 1, .column = 10 },
            .{ .type = "right_angle", .value = ">", .line = 1, .column = 11 },
            .{ .type = "exclamation", .value = "!", .line = 1, .column = 12 },
            .{ .type = "plus", .value = "+", .line = 1, .column = 13 },
            .{ .type = "minus", .value = "-", .line = 1, .column = 14 },
            .{ .type = "dot", .value = ".", .line = 1, .column = 15 },
            .{ .type = "colon", .value = ":", .line = 1, .column = 16 },
            .{ .type = "semicolon", .value = ";", .line = 1, .column = 17 },
            .{ .type = "slash", .value = "/", .line = 1, .column = 18 },
            .{ .type = "backslash", .value = "\\", .line = 1, .column = 19 },
            .{ .type = "equals", .value = "=", .line = 1, .column = 20 },
            .{ .type = "quote", .value = "\"", .line = 1, .column = 21 },
            .{ .type = "single_quote", .value = "'", .line = 1, .column = 22 },
            .{ .type = "question", .value = "?", .line = 1, .column = 23 },
            .{ .type = "comma", .value = ",", .line = 1, .column = 24 },
            .{ .type = "percent", .value = "%", .line = 1, .column = 25 },
            .{ .type = "at", .value = "@", .line = 1, .column = 26 },
            .{ .type = "dollar", .value = "$", .line = 1, .column = 27 },
            .{ .type = "caret", .value = "^", .line = 1, .column = 28 },
            .{ .type = "left_brace", .value = "{", .line = 1, .column = 29 },
            .{ .type = "right_brace", .value = "}", .line = 1, .column = 30 },
            .{ .type = "ampersand", .value = "&", .line = 1, .column = 31 },
            .{ .type = "pipe", .value = "|", .line = 1, .column = 32 },
            .{ .type = "eof", .value = "", .line = 1, .column = 33 },
        } },
        .{ .name = "windows_line_endings", .input = "Hello\r\nWorld", .expected = &[_]ExpectedToken{
            .{ .type = "text", .value = "Hello", .line = 1, .column = 1 },  // \r should NOT be included
            .{ .type = "newline", .value = "\n", .line = 1, .column = 6 },
            .{ .type = "text", .value = "World", .line = 2, .column = 1 },
            .{ .type = "eof", .value = "", .line = 2, .column = 6 },
        } },
        .{ .name = "multiple_carriage_returns", .input = "\r\r\rHello", .expected = &[_]ExpectedToken{
            .{ .type = "text", .value = "Hello", .line = 1, .column = 1 },  // Column should be 1, not 4
            .{ .type = "eof", .value = "", .line = 1, .column = 6 },
        } },
        .{ .name = "zero_width_space", .input = "Hello\u{200B}World", .expected = &[_]ExpectedToken{
            .{ .type = "text", .value = "Hello", .line = 1, .column = 1 },
            .{ .type = "zero_width_space", .value = "\u{200B}", .line = 1, .column = 6 },
            .{ .type = "text", .value = "World", .line = 1, .column = 6 }, // Zero-width space doesn't advance column
            .{ .type = "eof", .value = "", .line = 1, .column = 11 },
        } },
        .{ .name = "non_breaking_space", .input = "Hello\u{00A0}World", .expected = &[_]ExpectedToken{
            .{ .type = "text", .value = "Hello", .line = 1, .column = 1 },
            .{ .type = "non_breaking_space", .value = "\u{00A0}", .line = 1, .column = 6 },
            .{ .type = "text", .value = "World", .line = 1, .column = 7 },
            .{ .type = "eof", .value = "", .line = 1, .column = 12 },
        } },
        .{ .name = "control_characters", .input = "Hello\x00\x01World", .expected = &[_]ExpectedToken{
            .{ .type = "text", .value = "Hello", .line = 1, .column = 1 },
            .{ .type = "control_char", .value = "\x00", .line = 1, .column = 6 },
            .{ .type = "control_char", .value = "\x01", .line = 1, .column = 7 },
            .{ .type = "text", .value = "World", .line = 1, .column = 8 },
            .{ .type = "eof", .value = "", .line = 1, .column = 13 },
        } },
        .{ .name = "del_character", .input = "Hello\x7FWorld", .expected = &[_]ExpectedToken{
            .{ .type = "text", .value = "Hello", .line = 1, .column = 1 },
            .{ .type = "control_char", .value = "\x7F", .line = 1, .column = 6 },
            .{ .type = "text", .value = "World", .line = 1, .column = 7 },
            .{ .type = "eof", .value = "", .line = 1, .column = 12 },
        } },
        .{ .name = "mixed_nonprinting", .input = "A\u{200B}B\u{00A0}C\x00D", .expected = &[_]ExpectedToken{
            .{ .type = "text", .value = "A", .line = 1, .column = 1 },
            .{ .type = "zero_width_space", .value = "\u{200B}", .line = 1, .column = 2 },
            .{ .type = "text", .value = "B", .line = 1, .column = 2 }, // Zero-width doesn't advance
            .{ .type = "non_breaking_space", .value = "\u{00A0}", .line = 1, .column = 3 },
            .{ .type = "text", .value = "C", .line = 1, .column = 4 },
            .{ .type = "control_char", .value = "\x00", .line = 1, .column = 5 },
            .{ .type = "text", .value = "D", .line = 1, .column = 6 },
            .{ .type = "eof", .value = "", .line = 1, .column = 7 },
        } },
    };

    // Run tests for each case
    for (test_cases) |test_case| {
        var tokenizer = Tokenizer.init(test_case.input);

        for (test_case.expected, 0..) |expected, i| {
            const actual = tokenizer.next();
            const expected_type = stringToTokenType(expected.type);

            // Better error messages with test case context
            if (actual.type != expected_type) {
                std.debug.print("Test '{s}' failed at token {d}:\n", .{ test_case.name, i });
                std.debug.print("  Expected type: {s}, got: {s}\n", .{ @tagName(expected_type), @tagName(actual.type) });
                std.debug.print("  Input: '{s}'\n", .{test_case.input});
            }
            try std.testing.expectEqual(expected_type, actual.type);

            if (!std.mem.eql(u8, actual.value, expected.value)) {
                std.debug.print("Test '{s}' failed at token {d}:\n", .{ test_case.name, i });
                std.debug.print("  Expected value: '{s}', got: '{s}'\n", .{ expected.value, actual.value });
                std.debug.print("  Input: '{s}'\n", .{test_case.input});
            }
            try std.testing.expectEqualStrings(expected.value, actual.value);

            if (actual.line != expected.line) {
                std.debug.print("Test '{s}' failed at token {d}:\n", .{ test_case.name, i });
                std.debug.print("  Expected line: {d}, got: {d}\n", .{ expected.line, actual.line });
                std.debug.print("  Input: '{s}'\n", .{test_case.input});
            }
            try std.testing.expectEqual(expected.line, actual.line);

            if (actual.column != expected.column) {
                std.debug.print("Test '{s}' failed at token {d}:\n", .{ test_case.name, i });
                std.debug.print("  Expected column: {d}, got: {d}\n", .{ expected.column, actual.column });
                std.debug.print("  Input: '{s}'\n", .{test_case.input});
            }
            try std.testing.expectEqual(expected.column, actual.column);
        }
    }
}
