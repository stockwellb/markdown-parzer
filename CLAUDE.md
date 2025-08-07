# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a modular Markdown parser written in Zig following a **library-first design with CLI pipeline architecture**. The project demonstrates excellent software engineering principles with clear separation of concerns, composable design, and extensibility.

**Core Architecture Pattern:**
```
Input Markdown → [LEX] → ZON Tokens → [PARSE] → ZON MIR → [RENDER] → Output HTML
```

**Structure:**
- **Library Core (`src/`)**: All parsing logic as reusable modules
  - `root.zig` - Public API and library interface
  - `lexer.zig` - Complete tokenization engine with comprehensive test coverage
  - `parser.zig` - Complete MIR generation engine with full Markdown support
  - `html.zig` - HTML rendering engine
- **CLI Pipeline (`cmd/`)**: Unix-style composable tools
  - `cmd/lex/` - Tokenizer (markdown → ZON tokens)
  - `cmd/parse/` - Parser (tokens → ZON MIR)  
  - `cmd/html/` - HTML renderer (MIR → HTML)

## Build Commands

```bash
# Build the project
zig build

# Run individual commands
zig build run-lex    # Run lexer
zig build run-parse  # Run parser  
zig build run-html   # Run HTML renderer

# Run all tests
zig build test

# Run with optimization
zig build -Doptimize=ReleaseFast
zig build -Doptimize=ReleaseSmall
zig build -Doptimize=ReleaseSafe

# Build for specific target
zig build -Dtarget=x86_64-linux
```

## Pipeline Architecture

The markdown parser follows a modular pipeline architecture:

```bash
# Full pipeline
lex < input.md | parse | html > output.html

# Individual stages
echo "# Hello" | ./zig-out/bin/lex     # → ZON tokens
echo "# Hello" | lex | ./zig-out/bin/parse  # → ZON MIR  
echo "# Hello" | lex | parse | ./zig-out/bin/html  # → HTML
```

**Commands:**
- `lex` - Tokenizes markdown into ZON tokens
- `parse` - Converts tokens into ZON Markdown Intermediate Representation (MIR)
- `html` - Renders MIR to HTML with template support:
  - Default mode: `html` (uses built-in HTML5 template)
  - Custom template: `html template.html` (uses custom template file)
  - Body only: `html --body-only` (outputs content without HTML wrapper)

## Architecture & Design Patterns

### **Pipeline/Compiler Architecture**
The system implements a classic compiler pipeline with discrete, composable stages:

**Key Architectural Benefits:**
- **Modularity**: Each stage can be tested and developed independently
- **Composability**: Unix-style pipeline allows mixing and matching tools
- **Extensibility**: New output formats (PDF, LaTeX) can be added as new `cmd/` tools  
- **Debugging**: Intermediate ZON representations enable pipeline introspection

### **Key Abstractions & Interfaces**

1. **Lexer** (`src/lexer.zig`): 
   - **Complete Character Coverage**: Handles all Markdown special characters plus comprehensive non-printing character detection
   - **Non-printing Character Detection**: Zero-width spaces, control characters, non-breaking spaces, Unicode whitespace
   - **Position Tracking**: Accurate line/column information for error reporting with proper handling of zero-width characters
   - **Cross-platform Line Endings**: Proper handling of `\r\n` and `\r` characters
   - **Modular Design**: Clean separation of concerns with `collectText()` and `tryConsumeUnicodeNonPrinting()` functions
   - **Streaming Design**: Memory-efficient processing of large files
   - **Data-Driven Tests**: Comprehensive test coverage with structured test cases including edge cases
   - Key types: `Token`, `TokenType`, `Tokenizer`

2. **Parser** (`src/parser.zig`):
   - **Complete Implementation**: Full MIR generation for all major Markdown elements including headings, paragraphs, lists, fenced code blocks, emphasis, strong, inline code, and text
   - **Advanced Features**: Supports nested inline formatting (e.g., **`code`** renders as `<strong><code>code</code></strong>`)
   - **Tree Structure**: Parent-child relationships for nested elements with proper hierarchy
   - **Robust Parsing**: Handles all implemented Markdown elements with proper fallback for unrecognized tokens
   - **Memory Safety**: Proper allocation/deallocation with content cleanup in `Mir.deinit()`
   - **Loop Prevention**: Intelligent advancement logic prevents infinite loops on edge cases
   - **Optional Fields**: Flexible schema for different MIR types (`level` for headings, `content` for text/code)
   - **ZON Integration**: Proper ZON escaping for special characters in code blocks and text content
   - Key types: `Mir`, `MirType`, `Parser`

3. **HTML Renderer** (`src/html.zig`):
   - **Writer-based**: Works with any output stream using `anytype` writer
   - **Recursive Processing**: Handles nested document structures and inline formatting
   - **ZON Bridge**: Converts ZON MIR back to native structures for rendering using `std.zon.parse.fromSlice`
   - **Complete Element Support**: Renders all implemented Markdown elements (headings, paragraphs, lists, code blocks, emphasis, strong, inline code)
   - **Nested Formatting**: Properly handles complex nested structures like strong text containing code elements

4. **Library Interface** (`src/root.zig`):
   - **Clean API**: Re-exports all public types and functions
   - **High-level Functions**: `tokenize()` for complete tokenization, `printTokens()` for debugging
   - **ZON Serialization**: `tokensToZon()` for token serialization, `mirToZon()` for MIR serialization
   - **HTML Rendering**: `renderToHtml()`, `renderToHtmlWithTemplate()`, `renderToHtmlBody()` for flexible HTML output
   - **ZON Bridge Functions**: `zonMirToHtml()`, `zonMirToHtmlWithTemplate()`, `zonMirToHtmlBody()` for direct ZON processing
   - **Template System**: `default_html_template` constant and template placeholder support
   - **Component Access**: Direct access to `Tokenizer`, `Parser`, and HTML rendering functions
   - **Dependency Graph**: `root.zig` → `lexer.zig`, `parser.zig`, `html.zig`

### **Data Flow & Dependencies**
```
Raw Markdown → Token Stream (ZON) → MIR (ZON) → Target Format
     ↓              ↓                  ↓              ↓
   lexer.zig    cmd/lex/         cmd/parse/     cmd/html/
```

**Clean Dependency Architecture:**
- Library modules have minimal coupling
- CLI tools are thin wrappers around library functions
- ZON serves as universal intermediate representation

## Development Notes & Conventions

### **Code Quality & Conventions**
- **Naming**: PascalCase types (`TokenType`), camelCase functions (`renderMir`), snake_case files
- **Memory Management**: Explicit allocator patterns with proper deinit/destroy cleanup
- **Error Handling**: Zig's error union types throughout (`![]Token`, `!*Mir`)
- **Testing**: Embedded `test` blocks in each module with comprehensive coverage

### **Testing Architecture**
- **Data-Driven Testing**: Lexer uses structured test cases with expected/actual comparison
- **Comprehensive Coverage**: Tests for all single/multi-character tokens, edge cases, complex constructs
- **Integration Testing**: Full pipeline testing capability with ZON intermediates
- **Build Integration**: Parallel test execution across library and CLI components

### **Extension Points**
- **Parser Enhancements**: Add parsing logic for tables, blockquotes, horizontal rules, images, links (MIR types already defined, HTML rendering implemented)
- **New Output Formats**: Add `cmd/pdf/`, `cmd/latex/` etc. that consume ZON MIR
- **Advanced Template Features**: Template variables, conditional rendering, loops, includes
- **Enhanced HTML Rendering**: Syntax highlighting for code blocks, custom CSS classes, accessibility features
- **External Integration**: ZON pipeline enables integration with other languages/tools
- **Advanced Lexer Features**: Foundation ready for syntax highlighting, error recovery, incremental parsing
- **Extended List Support**: Ordered lists, nested lists, list item continuation

### **Architectural Decisions & Rationale**

**Why Separate CLI Commands vs Library?**
1. **Unix Philosophy**: Small, composable tools that do one thing well  
2. **Language Interop**: ZON interfaces enable integration with other languages
3. **Pipeline Debugging**: Ability to inspect intermediate stages
4. **Deployment Flexibility**: Can deploy individual stages or full pipeline

**Why ZON as Intermediate Format?**
1. **Native Integration**: Perfect fit for Zig's type system and memory model
2. **Human Readable**: Easy debugging and inspection with Zig syntax
3. **Type Safety**: Compile-time validation of data structures
4. **Performance**: Zero-copy parsing and efficient memory usage
5. **Tool Integration**: Enables integration with Zig ecosystem tools

**ZON Format Overview:**
ZON (Zig Object Notation) is Zig's native data format, similar to JSON but using Zig's struct syntax:
- Anonymous structs: `.{ .field = value }`
- Arrays: `.{ item1, item2, item3 }`
- Native Zig types and syntax
- Parsed using `std.zon.parse.fromSlice()` in the standard library

**Current Status:**
- **Production Ready**: Complete lexer-parser-renderer pipeline with comprehensive Markdown support
- **Fully Implemented**: All core components working with major Markdown elements (headings, paragraphs, lists, fenced code blocks, emphasis, strong, inline code)
- **Advanced Features**: Nested inline formatting, proper ZON escaping, robust error handling, HTML template system
- **Template System**: Complete HTML template support with custom templates, body-only mode, and CLI integration
- **Architecture Ready**: Extensible design for additional output formats and Markdown elements
- **Quality Assured**: Comprehensive test coverage, proper memory management, cross-platform support
- **Pipeline Verified**: Full end-to-end processing from complex Markdown documents to customizable HTML output
- **Recent Improvements**: Added HTML template system with `{content}` placeholder support, custom template file loading, body-only rendering mode, and enhanced CLI with template arguments

## Lexer Implementation Details

### **Advanced Tokenization Features**
- **Special Character Detection**: 39+ distinct token types covering all Markdown syntax
- **Non-printing Character Categorization**: 
  - Zero-width space (`\u200B`) 
  - Non-breaking space (`\u00A0`)
  - Control characters (0x00-0x1F, 0x7F)
  - Byte order mark (`\uFEFF`)
- **Text Collection**: `collectText()` function efficiently gathers consecutive text characters
- **Unicode Handling**: `tryConsumeUnicodeNonPrinting()` properly handles multi-byte Unicode sequences
- **Position Accuracy**: Zero-width characters don't advance column count, maintaining visual accuracy

### **Lexer Architecture Pattern**
The lexer follows a clean state machine pattern:
1. **Character Classification**: `getTokenType()`, `getNonPrintingTokenType()`, `getUnicodeNonPrintingType()`
2. **Position Management**: `advance()`, `peek()` with proper line/column tracking  
3. **Token Generation**: `makeToken()` creates tokens with position metadata
4. **Text Aggregation**: `collectText()` efficiently handles consecutive text characters

This modular design enables easy extension for new character types and preprocessing needs.

### **Key Parser Functions**
The parser includes specialized functions for different Markdown constructs:

- **`parseBlock()`**: Main block-level dispatcher (headings, paragraphs, lists, code blocks)
- **`parseHeading()`**: Handles `#`, `##`, `###` with level detection and inline content
- **`parseParagraph()`**: Multi-line text with smart termination logic for lists/headings
- **`parseList()`** / **`parseListItem()`**: Unordered list parsing with `-` and `*` markers
- **`parseCodeBlock()`**: Fenced code blocks with `` ``` `` detection and language identifiers
- **`parseInline()`**: Inline element dispatcher (text, emphasis, strong, code)
- **`parseEmphasisOrStrong()`**: `*` and `**` parsing with nested element support
- **`parseInlineSimple()`**: Nested parsing without recursion (prevents circular dependencies)
- **`parseCode()`**: Inline code spans with proper delimiter matching
- **`isCodeBlock()`** / **`isListItem()`**: Look-ahead functions for smart parsing decisions

## Parser Implementation Details

### **Core Parsing Architecture**
The parser implements a recursive descent parser that converts token streams into a structured MIR:

**Parsing Stages:**
1. **Block-level Parsing**: `parseBlock()` identifies and parses headings, paragraphs
2. **Inline Parsing**: `parseInline()` handles text, emphasis, strong, code within blocks
3. **Element-specific Parsers**: Dedicated functions for each Markdown construct

### **Implemented Markdown Elements**
- **Headings** (`# ## ###`): Proper level detection and content parsing with nested inline formatting
- **Paragraphs**: Multi-line text with full inline element support
- **Lists** (`- item`): Unordered lists with proper list item parsing and paragraph-list separation
- **Fenced Code Blocks** (`` ```lang ... ``` ``): Multi-line code blocks with language identifier support
- **Emphasis** (`*text*`): Single asterisk emphasis with nested element support
- **Strong** (`**text**`): Double asterisk strong emphasis with nested element support (e.g., **`code`**)
- **Inline Code** (`` `code` ``): Backtick-delimited code spans with proper escaping
- **Text**: All other content preserved as text nodes
- **Nested Formatting**: Complex combinations like strong text containing code elements

**MirType Enum Values** (defined but not all fully implemented):
- `document`, `heading`, `paragraph`, `text`
- `emphasis`, `strong`, `code`, `code_block`
- `list`, `list_item`
- `link`, `image` (enum defined, parser implementation pending)
- `blockquote`, `horizontal_rule` (enum defined, parser implementation pending)

### **Parser Architecture Pattern**
```
Token Stream → parseBlock() → Block Mirs (heading, paragraph, list, code_block)
                    ↓
              parseInline() → Inline Mirs (text, emphasis, strong, code)
                    ↓              ↓
            parseInlineSimple() → Nested Elements (code within strong)
                    ↓
              ZON MIR Output
```

**Key Implementation Features:**
- **Memory Safety**: Proper `Mir.deinit()` recursively frees content and children
- **Loop Prevention**: Smart advancement logic prevents infinite loops on unrecognized tokens
- **Fallback Handling**: Unmatched emphasis/code falls back to literal text
- **Position Tracking**: Maintains token position information through parsing
- **Hierarchical Structure**: Document → Blocks → Inline elements

### **Error Handling & Edge Cases**
- **Unmatched Emphasis**: `*text` without closing `*` becomes literal text
- **Incomplete Code**: `` `text`` without closing backtick becomes literal text  
- **Incomplete Fenced Code**: `` ```code`` without closing fence becomes literal text
- **Unknown Tokens**: Any unrecognized token advances parser position safely
- **Memory Management**: All allocated nodes properly cleaned up on error
- **Circular Dependencies**: `parseInlineSimple()` prevents recursion issues in nested formatting
- **ZON Escaping**: Special characters in content properly escaped for ZON format

## HTML Template System

### **Template Architecture**
The HTML renderer supports flexible template systems for custom document structures:

1. **Default Template**: Built-in modern HTML5 template with responsive meta tags
2. **Custom Templates**: User-provided HTML templates with `{content}` placeholder 
3. **Body-only Mode**: Renders just the markdown content without any wrapper HTML

### **Template Functions**

**Core Template Functions:**
- `renderToHtml()` - Uses default template (backward compatible)
- `renderToHtmlWithTemplate()` - Uses custom template with `{content}` placeholder
- `renderToHtmlBody()` - Renders content only, no HTML wrapper

**ZON Integration Functions:**
- `zonMirToHtml()` - ZON to HTML with default template
- `zonMirToHtmlWithTemplate()` - ZON to HTML with custom template
- `zonMirToHtmlBody()` - ZON to HTML body only

### **CLI Template Support**

The `html` command supports multiple modes:

```bash
# Default template (modern HTML5)
./zig-out/bin/html

# Custom template file
./zig-out/bin/html template.html

# Body-only mode (for embedding)
./zig-out/bin/html --body-only
```

### **Template Format**

Custom templates use a simple placeholder system:

```html
<!DOCTYPE html>
<html>
<head>
    <title>My Custom Document</title>
    <style>/* your styles */</style>
</head>
<body>
    <header>My Site Header</header>
    <main>
        {content}
    </main>
    <footer>My Site Footer</footer>
</body>
</html>
```

**Template Rules:**
- Templates must contain `{content}` placeholder where markdown content will be inserted
- If no `{content}` placeholder found, only the rendered content is returned
- Template files are read from the filesystem at runtime
- Error handling: Falls back to default template if custom template fails to load

## ZON Serialization Implementation

### **ZON Serialization Architecture**
The library provides first-class support for ZON serialization through dedicated functions:

1. **Token Serialization** (`tokensToZon()`):
   - Converts token arrays to ZON format using `std.Io.Writer.Allocating`
   - Handles all token types with proper enum serialization
   - Used by the `lex` CLI command for output

2. **MIR Serialization** (`mirToZon()`):
   - Converts recursive Mir structures to ZON format
   - Uses `SerializableMir` intermediate representation to handle recursive types
   - Employs `std.zon.stringify.serializeArbitraryDepth()` for deep nesting
   - Used by the `parse` CLI command for output

3. **SerializableMir Structure**:
   - Intermediate representation that converts `std.ArrayList(*Mir)` to slices
   - Required because ZON stringify cannot directly serialize ArrayLists
   - Maintains all node properties (type, content, level, children)
   - Properly manages memory allocation and deallocation

### **ZON vs JSON**
The project uses ZON (Zig Object Notation) instead of JSON for several reasons:
- **Native Integration**: Perfect fit for Zig's type system
- **Type Safety**: Enums are preserved as enums, not converted to strings
- **Performance**: Zero-copy parsing with `std.zon.parse.fromSlice()`
- **Readability**: Zig struct syntax is familiar to Zig developers

## Working Examples & Usage Patterns

### **Pipeline Usage Examples**
```bash
# Basic heading and text (default template)
echo "# Hello World" | ./zig-out/bin/lex | ./zig-out/bin/parse | ./zig-out/bin/html

# Custom template usage
echo "# Hello World" | ./zig-out/bin/lex | ./zig-out/bin/parse | ./zig-out/bin/html custom_template.html

# Body-only output (for embedding in existing pages)
echo "# Hello World" | ./zig-out/bin/lex | ./zig-out/bin/parse | ./zig-out/bin/html --body-only

# Emphasis and strong text with nested formatting
echo "This is **bold** and *italic* text" | ./zig-out/bin/lex | ./zig-out/bin/parse | ./zig-out/bin/html

# Lists
echo "- First item\n- Second item" | ./zig-out/bin/lex | ./zig-out/bin/parse | ./zig-out/bin/html

# Fenced code blocks
echo "\`\`\`zig\nconst std = @import(\"std\");\n\`\`\`" | ./zig-out/bin/lex | ./zig-out/bin/parse | ./zig-out/bin/html

# Full document processing with custom template
./zig-out/bin/lex < README.md | ./zig-out/bin/parse | ./zig-out/bin/html template.html > output.html

# Full document processing (default template)
./zig-out/bin/lex < README.md | ./zig-out/bin/parse | ./zig-out/bin/html > output.html
```

### **Library Usage Examples**
```zig
// High-level tokenization
const tokens = try markdown_parzer.tokenize(allocator, markdown_text);
defer allocator.free(tokens);

// Serialize tokens to ZON
const zon_tokens = try markdown_parzer.tokensToZon(allocator, tokens);
defer allocator.free(zon_tokens);

// Direct parser usage
var parser = markdown_parzer.Parser.init(allocator, tokens);
const mir = try parser.parse();
defer {
    mir.deinit(allocator);
    allocator.destroy(mir);
}

// Serialize MIR to ZON
const zon_mir = try markdown_parzer.mirToZon(allocator, mir);
defer allocator.free(zon_mir);

// HTML rendering with default template
const html = try markdown_parzer.renderToHtml(allocator, mir);
defer allocator.free(html);

// HTML rendering with custom template
const custom_template = "<html><body>{content}</body></html>";
const custom_html = try markdown_parzer.renderToHtmlWithTemplate(allocator, mir, custom_template);
defer allocator.free(custom_html);

// Body-only rendering (no HTML wrapper)
const body_only = try markdown_parzer.renderToHtmlBody(allocator, mir);
defer allocator.free(body_only);

// Direct ZON to HTML conversion with templates
const html_from_zon = try markdown_parzer.zonMirToHtml(allocator, zon_mir);
defer allocator.free(html_from_zon);

const custom_from_zon = try markdown_parzer.zonMirToHtmlWithTemplate(allocator, zon_mir, custom_template);
defer allocator.free(custom_from_zon);

const zon_body_only = try markdown_parzer.zonMirToHtmlBody(allocator, zon_mir);
defer allocator.free(zon_body_only);
```

### **ZON MIR Structure**
The parser produces clean, hierarchical ZON with proper nesting (using enum types, not strings):
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
                .{ .type = .text, .content = "Hello", .level = null, .children = .{} },
                .{ .type = .text, .content = " ", .level = null, .children = .{} },
                .{
                    .type = .strong,
                    .content = null,
                    .level = null,
                    .children = .{
                        .{ .type = .code, .content = "World", .level = null, .children = .{} }
                    }
                }
            }
        },
        .{
            .type = .list,
            .content = null,
            .level = null,
            .children = .{
                .{
                    .type = .list_item,
                    .content = null,
                    .level = null,
                    .children = .{
                        .{ .type = .text, .content = "Item 1", .level = null, .children = .{} }
                    }
                },
                .{
                    .type = .list_item,
                    .content = null,
                    .level = null,
                    .children = .{
                        .{ .type = .text, .content = "Item 2", .level = null, .children = .{} }
                    }
                }
            }
        },
        .{
            .type = .code_block,
            .content = "const std = @import(\"std\");",
            .level = null,
            .children = .{}
        }
    }
}
```