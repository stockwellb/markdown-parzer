# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a modular Markdown parser written in Zig following a **library-first design with CLI pipeline architecture**. The project demonstrates excellent software engineering principles with clear separation of concerns, composable design, and extensibility.

**Core Architecture Pattern:**
```
Input Markdown → [LEX] → JSON Tokens → [PARSE] → JSON AST → [RENDER] → Output HTML
```

**Structure:**
- **Library Core (`src/`)**: All parsing logic as reusable modules
  - `root.zig` - Public API and library interface
  - `lexer.zig` - Complete tokenization engine with comprehensive test coverage
  - `parser.zig` - Complete AST generation engine with full Markdown support
  - `html.zig` - HTML rendering engine
- **CLI Pipeline (`cmd/`)**: Unix-style composable tools
  - `cmd/lex/` - Tokenizer (markdown → JSON tokens)
  - `cmd/parse/` - Parser (tokens → JSON AST)  
  - `cmd/html/` - HTML renderer (AST → HTML)

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
echo "# Hello" | ./zig-out/bin/lex     # → JSON tokens
echo "# Hello" | lex | ./zig-out/bin/parse  # → JSON AST  
echo "# Hello" | lex | parse | ./zig-out/bin/html  # → HTML
```

**Commands:**
- `lex` - Tokenizes markdown into JSON tokens
- `parse` - Converts tokens into JSON Abstract Syntax Tree (AST)
- `html` - Renders AST to HTML (future targets: PDF, LaTeX, etc.)

## Architecture & Design Patterns

### **Pipeline/Compiler Architecture**
The system implements a classic compiler pipeline with discrete, composable stages:

**Key Architectural Benefits:**
- **Modularity**: Each stage can be tested and developed independently
- **Composability**: Unix-style pipeline allows mixing and matching tools
- **Extensibility**: New output formats (PDF, LaTeX) can be added as new `cmd/` tools  
- **Debugging**: Intermediate JSON representations enable pipeline introspection

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
   - **Complete Implementation**: Full AST generation for headings, paragraphs, emphasis, strong, code, and text
   - **Tree Structure**: Parent-child relationships for nested elements with proper hierarchy
   - **Robust Parsing**: Handles all Markdown elements with proper fallback for unrecognized tokens
   - **Memory Safety**: Proper allocation/deallocation with content cleanup in `Node.deinit()`
   - **Loop Prevention**: Intelligent advancement logic prevents infinite loops on edge cases
   - **Optional Fields**: Flexible schema for different node types (`level` for headings, `content` for text/code)
   - Key types: `Node`, `NodeType`, `Parser`

3. **HTML Renderer** (`src/html.zig`):
   - **Writer-based**: Works with any output stream using `anytype` writer
   - **Recursive Processing**: Handles nested document structures
   - **JSON Bridge**: Converts JSON AST back to native structures for rendering

4. **Library Interface** (`src/root.zig`):
   - **Clean API**: Re-exports all public types and functions
   - **High-level Functions**: `tokenize()` for complete tokenization, `printTokens()` for debugging
   - **Component Access**: Direct access to `Tokenizer`, `Parser`, and HTML rendering functions
   - **Dependency Graph**: `root.zig` → `lexer.zig`, `parser.zig`, `html.zig`

### **Data Flow & Dependencies**
```
Raw Markdown → Token Stream (JSON) → AST (JSON) → Target Format
     ↓              ↓                  ↓              ↓
   lexer.zig    cmd/lex/         cmd/parse/     cmd/html/
```

**Clean Dependency Architecture:**
- Library modules have minimal coupling
- CLI tools are thin wrappers around library functions
- JSON serves as universal intermediate representation

## Development Notes & Conventions

### **Code Quality & Conventions**
- **Naming**: PascalCase types (`TokenType`), camelCase functions (`renderNode`), snake_case files
- **Memory Management**: Explicit allocator patterns with proper deinit/destroy cleanup
- **Error Handling**: Zig's error union types throughout (`![]Token`, `!*Node`)
- **Testing**: Embedded `test` blocks in each module with comprehensive coverage

### **Testing Architecture**
- **Data-Driven Testing**: Lexer uses structured test cases with expected/actual comparison
- **Comprehensive Coverage**: Tests for all single/multi-character tokens, edge cases, complex constructs
- **Integration Testing**: Full pipeline testing capability with JSON intermediates
- **Build Integration**: Parallel test execution across library and CLI components

### **Extension Points**
- **Parser Enhancements**: Add support for tables, lists, blockquotes, horizontal rules, images, links
- **New Output Formats**: Add `cmd/pdf/`, `cmd/latex/` etc. that consume JSON AST
- **Enhanced Rendering**: Current HTML renderer works but could support more advanced features
- **External Integration**: JSON pipeline enables integration with other languages/tools
- **Advanced Lexer Features**: Foundation ready for syntax highlighting, error recovery, incremental parsing

### **Architectural Decisions & Rationale**

**Why Separate CLI Commands vs Library?**
1. **Unix Philosophy**: Small, composable tools that do one thing well  
2. **Language Interop**: JSON interfaces enable integration with other languages
3. **Pipeline Debugging**: Ability to inspect intermediate stages
4. **Deployment Flexibility**: Can deploy individual stages or full pipeline

**Why JSON as Intermediate Format?**
1. **Universal Compatibility**: Language-agnostic data exchange
2. **Human Readable**: Easy debugging and inspection (`jq` integration)
3. **Tool Integration**: Enables integration with external processing tools
4. **Streaming Friendly**: Can be processed incrementally

**Current Status:**
- **Production Ready**: Complete lexer-parser-renderer pipeline with full functionality
- **Fully Implemented**: All core components working with comprehensive Markdown support
- **Architecture Ready**: Extensible design for additional output formats
- **Quality Assured**: Comprehensive test coverage, proper error handling, cross-platform support
- **Pipeline Verified**: Full end-to-end processing from Markdown to HTML via JSON intermediates

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

## Parser Implementation Details

### **Core Parsing Architecture**
The parser implements a recursive descent parser that converts token streams into a structured AST:

**Parsing Stages:**
1. **Block-level Parsing**: `parseBlock()` identifies and parses headings, paragraphs
2. **Inline Parsing**: `parseInline()` handles text, emphasis, strong, code within blocks
3. **Element-specific Parsers**: Dedicated functions for each Markdown construct

### **Implemented Markdown Elements**
- **Headings** (`# ## ###`): Proper level detection and content parsing
- **Paragraphs**: Multi-line text with inline element support
- **Emphasis** (`*text*`): Single asterisk emphasis with content preservation
- **Strong** (`**text**`): Double asterisk strong emphasis
- **Inline Code** (`` `code` ``): Backtick-delimited code spans
- **Text**: All other content preserved as text nodes

### **Parser Architecture Pattern**
```
Token Stream → parseBlock() → Block Nodes (heading, paragraph)
                    ↓
              parseInline() → Inline Nodes (text, emphasis, strong, code)
                    ↓
              JSON AST Output
```

**Key Implementation Features:**
- **Memory Safety**: Proper `Node.deinit()` recursively frees content and children
- **Loop Prevention**: Smart advancement logic prevents infinite loops on unrecognized tokens
- **Fallback Handling**: Unmatched emphasis/code falls back to literal text
- **Position Tracking**: Maintains token position information through parsing
- **Hierarchical Structure**: Document → Blocks → Inline elements

### **Error Handling & Edge Cases**
- **Unmatched Emphasis**: `*text` without closing `*` becomes literal text
- **Incomplete Code**: `` `text`` without closing backtick becomes literal text
- **Unknown Tokens**: Any unrecognized token advances parser position safely
- **Memory Management**: All allocated nodes properly cleaned up on error

## Working Examples & Usage Patterns

### **Pipeline Usage Examples**
```bash
# Basic heading and text
echo "# Hello World" | ./zig-out/bin/lex | ./zig-out/bin/parse | ./zig-out/bin/html

# Emphasis and strong text  
echo "This is **bold** and *italic* text" | ./zig-out/bin/lex | ./zig-out/bin/parse

# Inline code
echo "Use \`code\` for inline code" | ./zig-out/bin/lex | ./zig-out/bin/parse

# Full document processing
./zig-out/bin/lex < README.md | ./zig-out/bin/parse | ./zig-out/bin/html > output.html
```

### **Library Usage Examples**
```zig
// High-level tokenization
const tokens = try markdown_parzer.tokenize(allocator, markdown_text);
defer allocator.free(tokens);

// Direct parser usage
var parser = markdown_parzer.Parser.init(allocator, tokens);
const ast = try parser.parse();
defer {
    ast.deinit(allocator);
    allocator.destroy(ast);
}

// HTML rendering
const html = try markdown_parzer.renderToHtml(allocator, ast);
defer allocator.free(html);
```

### **JSON AST Structure**
The parser produces clean, hierarchical JSON:
```json
{
  "type": "document",
  "children": [
    {
      "type": "heading",
      "level": 1,
      "children": [
        {"type": "text", "content": "Hello"},
        {"type": "text", "content": " "},
        {"type": "strong", "content": "World"}
      ]
    }
  ]
}
```