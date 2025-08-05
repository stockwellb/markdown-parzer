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
    
    // Parse markdown to HTML
    const markdown = "# Hello *World*";
    const html = try markdown_parzer.parseToHtml(allocator, markdown);
    defer allocator.free(html);
    
    // Or work with individual components
    var tokenizer = markdown_parzer.Tokenizer.init(markdown);
    while (true) {
        const token = tokenizer.next();
        if (token.type == .eof) break;
        // Process token...
    }
}
```

### Library Components

- **`Tokenizer`** - Core lexical analyzer (`src/lexer.zig`)
- **`Parser`** - AST builder *(in progress)*
- **`parseToHtml()`** - High-level convenience function  
- **`jsonAstToHtml()`** - Convert JSON AST to HTML

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
- Complete tokenization of all Markdown syntax elements
- Proper handling of whitespace (spaces, tabs, newlines preserved)
- Detection and categorization of non-printing characters (zero-width spaces, control chars, etc.)
- Accurate line/column tracking for error reporting
- Cross-platform line ending support (handles `\r\n` correctly)

### Parser
- JSON AST output for extensibility to multiple output formats
- *(Implementation in progress)*

### HTML Renderer  
- Clean HTML output from JSON AST
- Proper escaping and formatting

## Building

```bash
zig build
```

This creates executables in the build directory:
- `lex` - Lexical analyzer
- `parse` - Parser (outputs JSON AST)
- `html` - HTML renderer
