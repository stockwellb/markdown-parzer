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
  - `parser.zig` - AST generation framework (ready for implementation)
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
   - **Complete Character Coverage**: Handles all Markdown special characters
   - **Position Tracking**: Line/column information for error reporting
   - **Streaming Design**: Memory-efficient processing of large files
   - **Data-Driven Tests**: Comprehensive test coverage with structured test cases
   - Key types: `Token`, `TokenType`, `Tokenizer`

2. **Parser** (`src/parser.zig`):
   - **Tree Structure**: Parent-child relationships for nested elements
   - **Optional Fields**: Flexible schema for different node types (`level` for headings)
   - **Memory Management**: Explicit allocator-based lifecycle management
   - Key types: `Node`, `NodeType`, `Parser`

3. **HTML Renderer** (`src/html.zig`):
   - **Writer-based**: Works with any output stream using `anytype` writer
   - **Recursive Processing**: Handles nested document structures
   - **JSON Bridge**: Converts JSON AST back to native structures for rendering

4. **Library Interface** (`src/root.zig`):
   - **Clean API**: Re-exports all public types and functions
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
- **Ready for Implementation**: Parser framework in place, just needs AST building logic
- **New Output Formats**: Add `cmd/pdf/`, `cmd/latex/` etc. that consume JSON AST
- **Enhanced Rendering**: Current HTML renderer is basic but fully extensible
- **External Integration**: JSON pipeline enables integration with other languages/tools

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
- **Production Ready**: Lexer, CLI pipeline, basic HTML renderer, build system
- **Implementation Ready**: Parser framework prepared for AST generation logic
- **Architecture Ready**: Extensible design for additional output formats