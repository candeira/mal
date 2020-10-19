const std = @import("std");
const Allocator = std.mem.Allocator;
const allocator = std.heap.c_allocator;

const pcre2 = @cImport({
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
});

// by convention, zig strings are immutable slices of utf8
// for C, we need pointers, not slices.
// Zig will coerce automagically from Str = []const u8
// Not 0-sentineled because pcre2 accepts length
const c_Str = [*]const u8;

pub fn compile(pattern: c_Str) Pattern {
    return Pattern.init(pattern);
}

const Pattern = struct {
    pattern: ?c_Str = null,
    re_code: ?*pcre2.pcre2_code_8 = null,

    // Compiled RE is in C heap
    pub fn init(pattern: c_Str) Pattern {
        return Pattern{
            .pattern = pattern,
            // .re_code = pcre2.pcre2_compile_8(pattern),
        };
    }

    fn deinit(self: Pattern) void {
        pcre2.pcre2_code_free_8(self.re_code);
    }

    // fn _compile(pattern: c_Str) *pcre2.pcre2_code_8 {
    //     return pcre2.pcre2_compile_8();
    // }

    fn findall(self, string, flags) Result {}
};

const Result = struct {};

test "return a compiled Pattern" {
    const compiled = compile("");
    defer compiled.deinit();
}

// test "print the cImported pcre2 struct" {
//     const ti = @typeInfo(pcre2).Struct;
//     std.debug.warn("pcre2={}\n", .{ti});
//     inline for (ti.fields) |f| {
//         std.debug.print("\n");
//         std.debug.warn("{} ", .{f});
//     }
// }
