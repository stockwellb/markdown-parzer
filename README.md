# markdown-parzer

A modular Markdown parser written in Zig, designed as a Unix-style pipeline of composable tools.

## Architecture

The parser follows a three-stage pipeline architecture using ZON (Zig Object Notation) as the intermediate format:

```
Input Markdown → [LEX] → ZON Tokens → [PARSE] → ZON AST → [RENDER] → Output HTML
```

Each stage is a separate executable that reads from stdin and writes to stdout, allowing for flexible composition and debugging. The use of ZON provides type-safe, native Zig data exchange between pipeline stages.

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

    // Parse tokens into AST
    var parser = markdown_parzer.Parser.init(allocator, tokens);
    const ast = try parser.parse();
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    // Render to HTML
    const html = try markdown_parzer.renderToHtml(allocator, ast);
    defer allocator.free(html);
    try std.io.getStdOut().writeAll(html);

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
- `tokensToZon()` - Serialize tokens to ZON format for pipeline interchange
- `Parser` - Complete AST builder with support for all major Markdown elements
- `astToZon()` - Serialize AST to ZON format for pipeline interchange
- `renderToHtml()` - Render AST directly to HTML
- `zonAstToHtml()` - Convert ZON AST to HTML (bridge function)
- `printTokens()` - Debug utility to display tokens in human-readable format

## Command Line Tools

For debugging and pipeline composition, each stage is available as a standalone tool:

- **`lex`** - Tokenizes markdown text into categorized ZON tokens
- **`parse`** - Converts tokens into a ZON Abstract Syntax Tree (AST)
- **`html`** - Renders ZON AST to HTML output

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

- **Complete implementation** for all major Markdown elements:
  - Headings (`#`, `##`, `###`) with level detection
  - Paragraphs with automatic termination
  - Lists (`-`, `*`) with proper item parsing
  - Fenced code blocks (`` ``` ``) with language support
  - Emphasis (`*text*`) and strong (`**text**`) with nesting
  - Inline code (`` `code` ``)
  - Text nodes with proper whitespace handling
- **Nested inline formatting** - e.g., `**`bold code`**` works correctly
- **Memory-safe** with proper allocation/deallocation
- **ZON AST output** for type-safe data exchange

### HTML Renderer

- **Complete HTML generation** from ZON AST
- **All Markdown elements supported**:
  - Headings (`<h1>` through `<h6>`)
  - Paragraphs (`<p>`)
  - Lists (`<ul>`, `<li>`)
  - Code blocks (`<pre><code>`)
  - Emphasis (`<em>`) and strong (`<strong>`)
  - Inline code (`<code>`)
- **Nested element support** - handles complex formatting combinations
- **Proper escaping** for special characters

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

- `lex` - Lexical analyzer (outputs ZON tokens)
- `parse` - Parser (outputs ZON AST)
- `html` - HTML renderer

## Working Examples

### Full Pipeline
```bash
# Convert markdown to HTML
echo "# Hello **World**" | ./zig-out/bin/lex | ./zig-out/bin/parse | ./zig-out/bin/html

# Process a file
./zig-out/bin/lex < README.md | ./zig-out/bin/parse | ./zig-out/bin/html > output.html
```

### Debugging Individual Stages
```bash
# View tokens (ZON format)
echo "# Hello" | ./zig-out/bin/lex

# View AST (ZON format)
echo "# Hello" | ./zig-out/bin/lex | ./zig-out/bin/parse
```

### Complex Markdown Support
```bash
# Lists, code blocks, and nested formatting
cat << 'EOF' | ./zig-out/bin/lex | ./zig-out/bin/parse | ./zig-out/bin/html
# Project Overview

This is a paragraph with *italic* and **bold** text, plus `inline code`.

- First list item
- Second list item with **nested formatting**

```zig
const std = @import("std");
pub fn main() !void {
    std.debug.print("Hello, World!\n", .{});
}
```
EOF
```

## ZON Format

The project uses ZON (Zig Object Notation) instead of JSON for data interchange between pipeline stages. ZON provides:

- **Type Safety**: Enums are preserved as enums (e.g., `.heading` not `"heading"`)
- **Native Integration**: Perfect fit for Zig's type system
- **Performance**: Zero-copy parsing with `std.zon.parse.fromSlice()`
- **Readability**: Familiar Zig struct syntax

Example ZON AST output:
```zig
.{
    .type = .document,
    .content = null,
    .level = null,
    .children = .{
        .{
            .type = .heading,
            .content = null,
            .level = 1,
            .children = .{
                .{ .type = .text, .content = "Hello World", .level = null, .children = .{} }
            }
        }
    }
}
```


## Project Status

### ✅ Completed
- **Lexer**: Full tokenization with 39+ token types
- **Parser**: Complete AST generation for all major Markdown elements
- **HTML Renderer**: Full HTML output with nested element support
- **ZON Pipeline**: Type-safe data interchange between stages
- **Library API**: Clean, documented public interface
- **Test Coverage**: Comprehensive unit and integration tests

### 🚧 Planned Enhancements
- **Additional Markdown Elements**:
  - Links (`[text](url)`)
  - Images (`![alt](url)`)
  - Blockquotes (`>`)
  - Horizontal rules (`---`)
  - Tables
- **Output Formats**:
  - LaTeX renderer
  - PDF renderer
  - Terminal renderer with colors
- **Advanced Features**:
  - Syntax highlighting for code blocks
  - Custom HTML templates
  - Incremental parsing

## Requirements

- Zig 0.15.0 or later
- No external dependencies - uses only Zig standard library

## License

MIT License - See LICENSE file for details

## Contributing

Contributions are welcome! The codebase follows these conventions:
- PascalCase for types (`TokenType`, `Node`)
- camelCase for functions (`parseBlock`, `renderNode`)
- snake_case for files (`lexer.zig`, `parser.zig`)
- Comprehensive tests for all new features
- Memory safety with explicit allocation/deallocation
