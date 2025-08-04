# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Markdown parser written in Zig. The project is structured as both a library and CLI tool:
- **Library**: Exposed via `src/root.zig` (imported as `markdown_parzer`)
- **CLI**: Entry point at `src/main.zig`
- **Core functionality**: Lexer implementation in `src/lexer.zig`

## Build Commands

```bash
# Build the project
zig build

# Run the executable
zig build run

# Run all tests
zig build test

# Run with optimization
zig build -Doptimize=ReleaseFast
zig build -Doptimize=ReleaseSmall
zig build -Doptimize=ReleaseSafe

# Build for specific target
zig build -Dtarget=x86_64-linux
```

## Architecture

The parser follows a standard compiler architecture:

1. **Lexer** (`src/lexer.zig`): 
   - Tokenizes input into Markdown-specific tokens
   - Handles all special Markdown characters
   - Tracks line/column for error reporting
   - Key types: `Token`, `TokenType`, `Tokenizer`

2. **Library Interface** (`src/root.zig`):
   - Currently provides `bufferedPrint()` function
   - Entry point for library consumers

3. **CLI** (`src/main.zig`):
   - Imports the library module
   - Contains example tests including fuzz testing

## Development Notes

- The project uses Zig's built-in test framework
- Tests are included in source files and run with `zig build test`
- The lexer uses comprehensive data-driven tests covering:
  - All single character tokens (#, *, _, `, etc.)
  - Multi-character sequences (headings, bold, links)
  - Edge cases (whitespace, line tracking)
  - Complex markdown constructs
- Test data is structured for easy expansion and maintenance
- Special characters are tokenized individually for precise parsing