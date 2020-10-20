const std = @import("std");
const allocator = std.heap.c_allocator;

const pcre2 = @cImport({
    @cInclude("limits.h");
    @cInclude("stdlib.h");
    @cInclude("inttypes.h");
    @cInclude("stddef.h");
    @cInclude("stdio.h");
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
});

// zig strings are immutable slices of utf8
// for C, we need pointers, not slices.
// Not 0-sentineled because pcre2 accepts length
const Str = []const u8;
// const pcre2_size = pcre2.PCRE2_SIZE;
// can't find the values off pcre2.h;
// reverse engineering from compiler errors
const pcre2_errornumber_t = c_int;
const pcre2_erroroffset_t = usize;
const pcre2_errorlength_t = c_int;
const pcre2_errorbuffer_t = [256:0]u8;

// implement a limited repertoire of the Python re API
// matcher = re.compile("lala")
// matcher.findall("balaladamepanlala")
// ["lala", "lala"]

// Compiled RE code will be in C heap
// But Patern code lives in the stack
// Any error during pattern compilation will be stored
// in the Pattern object, and can be inspected later,
// will trigger when people try to match/find
pub fn compile(pattern: Str) Pattern {
    return Pattern.init(pattern);
}

const Pattern = struct {
    pattern: Str,
    re_code: ?*pcre2.pcre2_code_8 = null,
    errornumber: pcre2_errornumber_t = 0,
    erroroffset: pcre2_erroroffset_t = 0,
    errorbuffer: pcre2_errorbuffer_t = undefined,
    errorlength: pcre2_errorlength_t = 0,

    pub fn init(pattern: Str) Pattern {
        var errornumber: pcre2_errornumber_t = 0;
        var erroroffset: pcre2_erroroffset_t = 0;

        const re_code: ?*pcre2.pcre2_code_8 = pcre2.pcre2_compile_8(
            pattern.ptr,
            pattern.len,
            0,
            &errornumber,
            &erroroffset,
            null,
        );

        var matcher = Pattern{
            .pattern = pattern,
            .re_code = re_code,
            .errornumber = errornumber,
            .erroroffset = erroroffset,
        };

        if (re_code == null) {
            var errorbuffer = @ptrCast([*]u8, &matcher.errorbuffer);
            matcher.errorlength = pcre2.pcre2_get_error_message_8(
                errornumber,
                errorbuffer,
                @sizeOf(pcre2_errorbuffer_t),
            );
        }

        return matcher;
    }

    fn deinit(self: Pattern) void {
        if (self.re_code == null) {
            pcre2.pcre2_code_free_8(self.re_code);
        }
    }

    pub fn findall(self, string, flags) Result {}
};

const Result = struct {};

test "return a compiled Pattern" {
    const compiled = compile("foo");
    defer compiled.deinit();
}

test "return a Pattern containing an error" {
    const compiled = compile("[");
    std.debug.assert(compiled.errornumber == 106);
    const end = @bitCast(u32, compiled.errorlength);
    const expected = "missing terminating ] for character class";
    const message = compiled.errorbuffer[0..end];
    std.debug.assert(std.mem.eql(u8, expected, message));
    defer compiled.deinit();
}

// test "print the cImported pcre2 struct" {
//     const ti = @typeInfo(Pattern).Struct;
//     // std.debug.warn("pcre2={}\n", .{ti});
//     inline for (ti.fields) |f| {
//         std.debug.print("\n", .{});
//         std.debug.warn("{} ", .{f});
//     }
// }
