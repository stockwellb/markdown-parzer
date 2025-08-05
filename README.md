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

    // Render to HTML with default template
    const html = try markdown_parzer.renderToHtml(allocator, ast);
    defer allocator.free(html);
    
    // Or use custom template
    const custom_template = "<html><body>{content}</body></html>";
    const custom_html = try markdown_parzer.renderToHtmlWithTemplate(allocator, ast, custom_template);
    defer allocator.free(custom_html);
    
    // Or render body only (no HTML wrapper)
    const body_only = try markdown_parzer.renderToHtmlBody(allocator, ast);
    defer allocator.free(body_only);

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

**HTML Rendering:**
- `renderToHtml()` - Render AST to HTML with default template
- `renderToHtmlWithTemplate()` - Render AST to HTML with custom template
- `renderToHtmlBody()` - Render AST content only (no HTML wrapper)
- `zonAstToHtml()` - Convert ZON AST to HTML with default template
- `zonAstToHtmlWithTemplate()` - Convert ZON AST to HTML with custom template
- `zonAstToHtmlBody()` - Convert ZON AST to content only
- `default_html_template` - Built-in HTML5 template constant
- `printTokens()` - Debug utility to display tokens in human-readable format

## Command Line Tools

For debugging and pipeline composition, each stage is available as a standalone tool:

- **`lex`** - Tokenizes markdown text into categorized ZON tokens
- **`parse`** - Converts tokens into a ZON Abstract Syntax Tree (AST)
- **`html`** - Renders ZON AST to HTML output with template support:
  - `html` - Uses built-in HTML5 template
  - `html template.html` - Uses custom template file with `{content}` placeholder
  - `html --body-only` - Outputs content only (no HTML wrapper)

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

- **Complete implementation** for all major Markdown elements
- **Headings** (`#`, `##`, `###`) with level detection
- **Paragraphs** with automatic termination
- **Lists** (`-`, `*`) with proper item parsing
- **Fenced code blocks** with language support
- **Emphasis** (`*text*`) and strong (`**text**`) with nesting
- **Inline code** with backtick delimiters
- **Text nodes** with proper whitespace handling
- **Nested inline formatting** - e.g., bold text containing inline code works correctly
- **Memory-safe** with proper allocation/deallocation
- **ZON AST output** for type-safe data exchange

### HTML Renderer

- **Complete HTML generation** from ZON AST
- **All Markdown elements supported**
- **Headings** (h1 through h6 tags)
- **Paragraphs** (p tags)
- **Lists** (ul and li tags)
- **Code blocks** (pre and code tags)
- **Emphasis** (em tags) and strong (strong tags)
- **Inline code** (code tags)
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
- `html` - HTML renderer with template support

## HTML Template System

The parser includes a flexible template system for customizing HTML output:

### Template Options

**Default Template:** Uses built-in HTML5 template with responsive meta tags

**Custom Template:** Uses your template file with content placeholder 

**Body Only:** Outputs just the content without HTML wrapper (perfect for embedding)

### Usage Examples

Convert markdown with different template modes:

- Default: `echo "# Hello" | lex | parse | html`
- Custom: `echo "# Hello" | lex | parse | html template.html`  
- Body only: `echo "# Hello" | lex | parse | html --body-only`

### Custom Template Format

Create a template file with content placeholder:

```
Template structure:
- HTML document wrapper
- HEAD section with title and styles  
- BODY with header, main content area, footer
- {content} placeholder in main section
```

Your template.html should include standard HTML structure with a {content} placeholder where you want the markdown content inserted.

**Template Rules:**
- Must contain `{content}` placeholder where markdown content will be inserted
- If no placeholder found, only the rendered content is returned
- Template files are loaded at runtime
- Falls back to default template if custom template fails to load

## Working Examples

### Full Pipeline
```bash
# Convert markdown to HTML (default template)
echo "# Hello **World**" | ./zig-out/bin/lex | ./zig-out/bin/parse | ./zig-out/bin/html

# Convert with custom template
echo "# Hello **World**" | ./zig-out/bin/lex | ./zig-out/bin/parse | ./zig-out/bin/html template.html

# Convert to body-only (for embedding)
echo "# Hello **World**" | ./zig-out/bin/lex | ./zig-out/bin/parse | ./zig-out/bin/html --body-only

# Process a file with default template
./zig-out/bin/lex < README.md | ./zig-out/bin/parse | ./zig-out/bin/html > output.html

# Process a file with custom template
./zig-out/bin/lex < README.md | ./zig-out/bin/parse | ./zig-out/bin/html template.html > output.html
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
# Lists and nested formatting
echo "# Project Overview

This is a paragraph with *italic* and **bold** text.

- First list item
- Second list item with **nested formatting**" | ./zig-out/bin/lex | ./zig-out/bin/parse | ./zig-out/bin/html
```

## ZON Format

The project uses ZON (Zig Object Notation) instead of JSON for data interchange between pipeline stages. ZON provides:

- **Type Safety**: Enums are preserved as enums (e.g., `.heading` not `"heading"`)
- **Native Integration**: Perfect fit for Zig's type system
- **Performance**: Zero-copy parsing with `std.zon.parse.fromSlice()`
- **Readability**: Familiar Zig struct syntax

Example ZON AST output shows the hierarchical structure with enum types for node types, null values for unused fields, and nested children arrays.


## Project Status

### ✅ Completed
- **Lexer**: Full tokenization with 39+ token types
- **Parser**: Complete AST generation for all major Markdown elements
- **HTML Renderer**: Full HTML output with nested element support
- **Template System**: Custom HTML templates with `{content}` placeholder support
- **CLI Template Support**: Default, custom template, and body-only modes
- **ZON Pipeline**: Type-safe data interchange between stages
- **Library API**: Clean, documented public interface with template functions
- **Test Coverage**: Comprehensive unit and integration tests

### 🚧 Planned Enhancements
- **Additional Markdown Elements**: Links, Images, Blockquotes, Horizontal rules (HTML rendering implemented, parser logic needed), Tables, Ordered lists, Nested lists
- **Output Formats**: LaTeX renderer, PDF renderer, Terminal renderer with colors
- **Advanced Template Features**: Template variables, conditional rendering, loops, includes
- **Enhanced Features**: Syntax highlighting for code blocks, Incremental parsing

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
