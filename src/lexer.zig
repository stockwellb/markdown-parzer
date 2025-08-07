//! Lexical analyzer for Markdown text
//!
//! This module provides a comprehensive tokenizer for Markdown documents,
//! breaking input text into discrete tokens for further processing.
//! The lexer handles all standard Markdown syntax elements, special characters,
//! and non-printing Unicode characters.
//!
//! ## Features
//! - Complete Markdown syntax support (39+ token types)
//! - Non-printing character detection (zero-width spaces, control chars, etc.)
//! - Accurate line/column position tracking for error reporting
//! - Cross-platform line ending support (\r\n, \r, \n)
//! - Memory-efficient streaming design
//! - No allocations required (operates on input slice)
//!
//! ## Usage
//! ```zig
//! var tokenizer = Tokenizer.init("# Hello World");
//! while (true) {
//!     const token = tokenizer.next();
//!     if (token.type == .eof) break;
//!     // Process token
//! }
//! ```

const std = @import("std");

/// Token types representing all possible lexical elements in Markdown
///
/// The TokenType enum categorizes every character and character sequence
/// that has significance in Markdown parsing. This includes:
/// - Single character tokens for Markdown syntax
/// - Multi-character tokens for text and digits
/// - Non-printing character tokens for special Unicode handling
/// - EOF token to signal end of input
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

/// A single token produced by the lexer
///
/// Each token captures:
/// - The type of token (what kind of Markdown element)
/// - The actual text value from the input
/// - The position where the token started (line and column)
///
/// Position information is crucial for error reporting and
/// maintaining source mapping through the parsing pipeline.
pub const Token = struct {
    /// The type of this token
    type: TokenType,
    /// The raw text value from the input (slice into original input)
    value: []const u8,
    /// Line number where this token starts (1-based)
    line: u32,
    /// Column number where this token starts (1-based)
    column: u32,
};

/// Streaming tokenizer for Markdown text
///
/// The Tokenizer processes input text character by character,
/// producing a stream of tokens. It maintains internal state
/// for position tracking and operates without allocations.
///
/// ## Design
/// - Zero allocations: operates entirely on the input slice
/// - Single pass: O(n) time complexity
/// - Streaming: can process arbitrarily large inputs
/// - Stateful: maintains position for accurate error reporting
///
/// ## Line Ending Handling
/// The tokenizer normalizes line endings by:
/// - Treating \n as the canonical newline token
/// - Silently consuming \r characters
/// - Properly handling \r\n (Windows) and \r (old Mac) endings
pub const Tokenizer = struct {
    /// The complete input text being tokenized (not owned by tokenizer)
    input: []const u8,
    /// Current byte position in the input
    position: usize = 0,
    /// Current line number (1-based)
    line: u32 = 1,
    /// Current column number (1-based)
    column: u32 = 1,

    /// Initialize a new tokenizer with the given input string
    ///
    /// The tokenizer does not take ownership of the input slice.
    /// The caller must ensure the input remains valid for the
    /// lifetime of the tokenizer.
    ///
    /// Parameters:
    ///   - input: The Markdown text to tokenize
    ///
    /// Returns: A new tokenizer ready to produce tokens
    pub fn init(input: []const u8) Tokenizer {
        return Tokenizer{ .input = input };
    }

    /// Get the next token from the input stream
    ///
    /// This is the main tokenization function. It examines the current
    /// position in the input and produces the appropriate token.
    ///
    /// The tokenizer automatically:
    /// - Skips carriage return characters (\r)
    /// - Detects multi-byte Unicode sequences
    /// - Aggregates consecutive text characters
    /// - Tracks line and column positions
    ///
    /// Returns: The next token, or EOF token when input is exhausted
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
    ///
    /// Detects and consumes specific Unicode non-printing characters:
    /// - Zero-width space (U+200B): 3 bytes, no visual width
    /// - Byte order mark (U+FEFF): 3 bytes, usually invisible
    /// - Non-breaking space (U+00A0): 2 bytes, takes one column
    ///
    /// Parameters:
    ///   - start_line: Line number where token started
    ///   - start_column: Column number where token started
    ///   - start_pos: Byte position where token started
    ///
    /// Returns: Token if Unicode non-printing character found, null otherwise
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

    /// Collect consecutive text characters into a single text token
    ///
    /// This function aggregates multiple consecutive non-special characters
    /// into a single text token for efficiency. It stops when encountering:
    /// - Any Markdown special character
    /// - Any non-printing character
    /// - Carriage return (\r)
    /// - End of input
    ///
    /// This aggregation reduces the number of tokens and improves
    /// parser performance for large blocks of plain text.
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
    ///
    /// Peek is used for lookahead operations without advancing
    /// the tokenizer position. Essential for multi-character
    /// token detection.
    ///
    /// Returns: Current character, or null if at end of input
    fn peek(self: *const Tokenizer) ?u8 {
        if (self.position >= self.input.len) return null;
        return self.input[self.position];
    }

    /// Consume the current character and advance position
    ///
    /// Advances the tokenizer by one byte and updates position tracking:
    /// - Increments column for most characters
    /// - Increments line and resets column for newlines
    /// - Handles multi-byte sequences correctly
    ///
    /// This function maintains the invariant that line/column
    /// always reflect the visual position in the source text.
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

    /// Skip carriage return characters (\r)
    ///
    /// Markdown treats \r as insignificant, normalizing all line endings
    /// to \n tokens. This function silently consumes \r characters without
    /// updating line/column tracking, maintaining cross-platform compatibility.
    ///
    /// Note: Spaces, tabs, and newlines are significant in Markdown and
    /// are NOT skipped - they produce their own tokens.
    fn skipCarriageReturn(self: *Tokenizer) void {
        while (self.position < self.input.len and 
               self.input[self.position] == '\r') {
            self.position += 1;  // Just increment position, don't update line/column
        }
    }

    /// Create a token from the current tokenizer state
    ///
    /// Constructs a Token struct with the given type and position information.
    /// The token's value is a slice from start_pos to current position.
    ///
    /// Parameters:
    ///   - token_type: The type of token to create
    ///   - start_line: Line where the token started
    ///   - start_column: Column where the token started
    ///   - start_pos: Byte position where the token started
    ///
    /// Returns: A new Token with the specified properties
    fn makeToken(self: *const Tokenizer, token_type: TokenType, start_line: u32, start_column: u32, start_pos: usize) Token {
        return Token{
            .type = token_type,
            .value = self.input[start_pos..self.position],
            .line = start_line,
            .column = start_column,
        };
    }

    /// Classify single-byte non-printing characters
    ///
    /// Detects ASCII control characters and other non-printing bytes:
    /// - Control characters (0x00-0x1F) except tab/newline/carriage return
    /// - DEL character (0x7F)
    /// - Non-breaking space in Latin-1 encoding (0xA0)
    ///
    /// Parameters:
    ///   - c: The byte to classify
    ///
    /// Returns: TokenType for non-printing character, or null if printable
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
    
    /// Detect multi-byte Unicode non-printing characters
    ///
    /// Examines the byte sequence starting at current position to detect
    /// UTF-8 encoded non-printing characters. Currently detects:
    /// - Zero-width space (U+200B): E2 80 8B
    /// - Byte order mark (U+FEFF): EF BB BF
    /// - Non-breaking space (U+00A0): C2 A0
    ///
    /// This function does NOT consume the bytes - it only detects them.
    /// Use tryConsumeUnicodeNonPrinting() to actually consume them.
    ///
    /// Returns: TokenType if Unicode non-printing sequence detected, null otherwise
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
    
    /// Map a single character to its token type
    ///
    /// Central dispatch function that classifies ASCII characters
    /// into their Markdown token types. This includes all special
    /// characters used in Markdown syntax.
    ///
    /// Parameters:
    ///   - c: The character to classify
    ///
    /// Returns: TokenType for the character, or null if not a special character
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

// Test data structures for comprehensive testing
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

/// Convert a string representation to a TokenType enum value
///
/// Used in testing to convert expected token type strings to enums.
/// Panics if the string doesn't match any TokenType.
///
/// Parameters:
///   - type_str: String name of the token type
///
/// Returns: Corresponding TokenType enum value
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
