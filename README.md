# markdown-parzer

A modular Markdown parser written in Zig, designed as a Unix-style pipeline of composable tools.

## Architecture

The parser follows a three-stage pipeline architecture:

```
Input Markdown → [LEX] → JSON Tokens → [PARSE] → JSON AST → [RENDER] → Output HTML
```

Each stage is a separate executable that reads from stdin and writes to stdout, allowing for flexible composition and debugging.

## Library Usage

The primary interface is the Zig library. Import and use the parsing components directly:

```zig
const std = @import("std");
const markdown_parzer = @import("markdown_parzer");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Tokenize markdown input
    const markdown = "# Hello *World*";
    const tokens = try markdown_parzer.tokenize(allocator, markdown);
    defer allocator.free(tokens);

    // Print tokens for debugging
    try markdown_parzer.printTokens(std.io.getStdOut().writer(), tokens);

    // Or work with tokenizer directly
    var tokenizer = markdown_parzer.Tokenizer.init(markdown);
    while (true) {
        const token = tokenizer.next();
        if (token.type == .eof) break;
        // Process token...
    }
}
```

### Library Components

- `Tokenizer` - Core lexical analyzer with advanced non-printing character detection
- `tokenize()` - High-level function to tokenize markdown and return all tokens
- `printTokens()` - Debug utility to display tokens in human-readable format
- `Parser` - AST builder _(framework ready, implementation in progress)_
- `renderToHtml()`, `renderNode()`, `jsonAstToHtml()` - HTML rendering functions

## Command Line Tools

For debugging and pipeline composition, each stage is available as a standalone tool:

- **`lex`** - Tokenizes markdown text into categorized JSON tokens
- **`parse`** - Converts tokens into a JSON Abstract Syntax Tree (AST)
- **`html`** - Renders JSON AST to HTML output

```bash
# Full pipeline
echo "# Hello *World*" | lex | parse | html

# Individual stages for debugging
echo "# Hello" | lex                    # See raw tokens
echo "# Hello" | lex | parse            # See AST structure
```

## Features

### Lexer

- **Complete tokenization** of 39+ Markdown syntax elements and special characters
- **Whitespace preservation** - spaces, tabs, newlines maintained as distinct tokens
- **Non-printing character detection** - zero-width spaces, control characters, non-breaking spaces, byte order marks
- **Accurate position tracking** - line/column information with proper handling of zero-width characters
- **Cross-platform line endings** - robust handling of `\r\n`, `\r`, and `\n`
- **Modular architecture** - clean separation with `collectText()` and Unicode handling functions
- **Comprehensive test coverage** - data-driven tests with edge cases and error conditions

### Parser

- JSON AST output for extensibility to multiple output formats
- _(Implementation in progress)_

### HTML Renderer

- Clean HTML output from JSON AST
- Proper escaping and formatting

## Building

```bash
# Build all executables
zig build

# Run individual tools
zig build run-lex                    # Run lexer
zig build run-parse                  # Run parser
zig build run-html                   # Run HTML renderer

# Run all tests
zig build test

# Build with optimization
zig build -Doptimize=ReleaseFast     # Optimize for speed
zig build -Doptimize=ReleaseSmall    # Optimize for size
zig build -Doptimize=ReleaseSafe     # Optimize with safety checks
```

This creates executables in `zig-out/bin/`:

- `lex` - Lexical analyzer
- `parse` - Parser (outputs JSON AST)
- `html` - HTML renderer
