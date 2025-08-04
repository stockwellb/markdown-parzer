//! Use `zig init --strip` next time to generate a project without comments.
const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const mod = b.addModule("markdown_parzer", .{
        // The root source file is the "entry point" of this module. Users of
        // this module will only be able to access public declarations contained
        // in this file, which means that if you have declarations that you
        // intend to expose to consumers that were defined in other files part
        // of this module, you will have to make sure to re-export them from
        // the root file.
        .root_source_file = b.path("src/root.zig"),
        // Later on we'll use this module as the root module of a test executable
        // which requires us to specify a target.
        .target = target,
    });

    // Create the lexer executable
    const lex_exe = b.addExecutable(.{
        .name = "lex",
        .root_module = b.createModule(.{
            .root_source_file = b.path("cmd/lex/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "markdown_parzer", .module = mod },
            },
        }),
    });

    // Create the parser executable
    const parse_exe = b.addExecutable(.{
        .name = "parse",
        .root_module = b.createModule(.{
            .root_source_file = b.path("cmd/parse/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "markdown_parzer", .module = mod },
            },
        }),
    });

    // Create the HTML renderer executable
    const html_exe = b.addExecutable(.{
        .name = "html",
        .root_module = b.createModule(.{
            .root_source_file = b.path("cmd/html/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "markdown_parzer", .module = mod },
            },
        }),
    });

    // Install all executables
    b.installArtifact(lex_exe);
    b.installArtifact(parse_exe);
    b.installArtifact(html_exe);

    // Create run steps for all executables
    const run_lex_step = b.step("run-lex", "Run the lexer");
    const run_lex_cmd = b.addRunArtifact(lex_exe);
    run_lex_step.dependOn(&run_lex_cmd.step);
    run_lex_cmd.step.dependOn(b.getInstallStep());

    const run_parse_step = b.step("run-parse", "Run the parser");
    const run_parse_cmd = b.addRunArtifact(parse_exe);
    run_parse_step.dependOn(&run_parse_cmd.step);
    run_parse_cmd.step.dependOn(b.getInstallStep());

    const run_html_step = b.step("run-html", "Run the HTML renderer");
    const run_html_cmd = b.addRunArtifact(html_exe);
    run_html_step.dependOn(&run_html_cmd.step);
    run_html_cmd.step.dependOn(b.getInstallStep());

    // Default run step runs the lexer
    const run_step = b.step("run", "Run the lexer (default)");
    run_step.dependOn(run_lex_step);

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_lex_cmd.addArgs(args);
        run_parse_cmd.addArgs(args);
        run_html_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the lexer executable
    const lex_tests = b.addTest(.{
        .root_module = lex_exe.root_module,
    });

    // Creates an executable that will run `test` blocks from the parser executable
    const parse_tests = b.addTest(.{
        .root_module = parse_exe.root_module,
    });

    // Creates an executable that will run `test` blocks from the html executable
    const html_tests = b.addTest(.{
        .root_module = html_exe.root_module,
    });

    // Run steps for test executables
    const run_lex_tests = b.addRunArtifact(lex_tests);
    const run_parse_tests = b.addRunArtifact(parse_tests);
    const run_html_tests = b.addRunArtifact(html_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the run steps do not depend on one another, this will
    // make them run in parallel.
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_lex_tests.step);
    test_step.dependOn(&run_parse_tests.step);
    test_step.dependOn(&run_html_tests.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
