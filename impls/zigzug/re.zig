const std = @import("std");
const allocator = std.heap.c_allocator;
const assert = std.debug.assert;
const mem = std.mem;

const pcre2 = @cImport({
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
});

// String types used for wrapping the pcre2 regular expression library.
//
// These are runtime types, not comptime types.
// When writing tests, ensure the values passed are not comptime
// because the slices will have different types in either case!
//
// https://ziglang.org/download/0.6.0/release-notes.html#Slicing-with-Comptime-Indexes

// Zig strings are immutable slices of utf8
// String literals are zero-terminated, but we don't want that:
// - pcre2 already uses pointer, length for inputs and outputs.
// - our regex match results will be backed by the target string,
//   so we can't zero terminate them.
const Str = []const u8;

// A re.Matches type is a list of match results.
// Its Zig type is a slice of Strs ([][]const u8, once dealiased)
// Matches storage is as follows:
// - list of match results (outer slice): TODO: heap or stack?
// - each match result Str: backed by the target string's buffer
const Matches = []Str;

// re.zero_matches is an empty slice of Strs,
// And we need to initialise it as runtime! (see above)
var zero_matches: Matches = zeroMatches();

fn zeroMatches() Matches {
    return &[0]Str{};
}

// OLD CODE REMOVE
// const zero_array_of_zero_strings = [0]Str{};
// const zero_matches: Matches = zero_array_of_zero_strings[0..];
// ifreund's "more idiomatic version"
// const zero_matches: [][]const u8 = &[0]const u8{};

// TODO: move all pcre2 imports to their own struct
const pcre2_size = pcre2.PCRE2_SIZE;
// can't find the values off pcre2.h;
// reverse engineering from compiler errors
const pcre2_errornumber_t = c_int;
const pcre2_erroroffset_t = usize;
const pcre2_errorlength_t = c_int;
const pcre2_errorbuffer_t = [256:0]u8;
const pcre2_match_data_t = pcre2.struct_pcre2_real_match_data_8;

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
    match_data: *pcre2_match_data_t = undefined,

    pub fn errormessage(self: Pattern) ?Str {
        if (self.re_code == null) {
            const end = @bitCast(u32, self.errorlength);
            return self.errorbuffer[0..end];
        } else {
            return null;
        }
    }

    pub fn init(pattern: Str) Pattern {
        var errornumber: pcre2_errornumber_t = 0;
        var erroroffset: pcre2_erroroffset_t = 0;

        // the compiled pcre2 code object
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
            // if there's a compilation error, find the corresponding message
            var errorbuffer = @ptrCast([*]u8, &matcher.errorbuffer);
            matcher.errorlength = pcre2.pcre2_get_error_message_8(
                errornumber,
                errorbuffer,
                @sizeOf(pcre2_errorbuffer_t),
            );
        } else {
            // If there's no compilation error, create the match_data structure.
            // As far as Zig knows, *pcre2.bar pcre2.foo() functions could return null pointers,
            // so the zig return type is optional pointer ?*pcre2.bar and not *pcre2.bar
            //
            matcher.match_data = pcre2.pcre2_match_data_create_from_pattern_8(re_code, null).?;
        }

        return matcher;
    }

    pub fn deinit(self: Pattern) void {
        if (self.re_code == null) {
            pcre2.pcre2_match_data_free_8(self.match_data);
            pcre2.pcre2_code_free_8(self.re_code);
        }
    }

    // Allocates an array of matches, backed by the matching string.
    // Caller becomes owner of memory.
    // Still using C Heap because life's too short
    pub fn findall(self: Pattern, string: Str) !Matches {
        var first_match = pcre2.pcre2_match_8(
            self.re_code,
            @ptrCast([*]const u8, string),
            string.len,
            0,
            0,
            self.match_data,
            null,
        );

        // TODO: too difficult now
        // finish later when we list all possible errors
        const MatchCode = enum(c_int) {
            Success = 0,
            NoMatch = pcre2.PCRE2_ERROR_NOMATCH,
        };

        switch (first_match) {
            0 => {},
            pcre2.PCRE2_ERROR_NOMATCH => {
                return zero_matches;
            },
            else => {
                self._setError("Error while attempting a match! TODO: match each error to a descriptive message");
                return error.PCRE2MatchingError;
            },
        }

        // we have one match, now we continue matching and building

        return zero_matches;
    }

    pub fn _setError(self: Pattern, message: Str) void {
        // const len = message.len;
        // self.errorlength.* = len;
        // &self.errorbuffer.* = message;
        // mem.copy(u8, self.errorbuffer[0..len], message[0..len]);
    }
};

// TESTS
//

fn Str_equal(a: Str, b: Str) bool {
    return mem.eql(u8, a, b);
}

var buffer = "fool me once, fool me twice";
// make indices runtime known only, because comptime/runtime index slicing gives different types
// https://ziglang.org/download/0.6.0/release-notes.html#Slicing-with-Comptime-Indexes
var zero: usize = 0;
var three: usize = 3;
var five: usize = 5;
var seven: usize = 7;
var fourteen: usize = 14;
var seventeen: usize = 17;
var nineteen: usize = 19;
var twentyone: usize = 21;
// however, making foo1 and foo2 'var' doesn't do enough to make them runtime
// and the compiler gives off this error:
//     ./re.zig:174:23: error: cannot store runtime value in compile time variable
//         var foo1: Str = buffer[zero..three];
//                               ^
//         ./re.zig:197:45: note: referenced here
//         var matches1: Matches = &[_][]const u8{ foo1, me1 };
//                                                 ^
// so let's comment them out, move the rest to the test blocks:
// var foo1: Str = buffer[zero..three];
// var foo2: Str = buffer[fourteen..seventeen];

test "Str_equal" {
    var foo1: Str = buffer[zero..three];
    var foo2: Str = buffer[fourteen..seventeen];
    assert(Str_equal(foo1, foo2));
}

fn Matches_equal(a: Matches, b: Matches) bool {
    if (a.len != b.len) {
        return false;
    }
    for (a[0..a.len]) |item_a, i| {
        var item_b = b[i];
        if (!Str_equal(item_a, item_b)) {
            return false;
        }
    }
    return true;
}

test "Matches_equal" {
    var foo1: Str = buffer[zero..three];
    var foo2: Str = buffer[fourteen..seventeen];
    var me1: Str = buffer[five..seven];
    var me2: Str = buffer[nineteen..twentyone];
    var matches1: Matches = &[_][]const u8{ foo1, me1 };
    var matches2: Matches = &[_][]const u8{ foo2, me2 };
    assert(Matches_equal(matches1, matches2));
}

test "return a compiled Pattern" {
    const compiled = compile("foo");
    defer compiled.deinit();
    assert(compiled.re_code != null);
    assert(compiled.errormessage() == null);
}

// test "return a Pattern containing an error" {
//     const compiled = compile("[");
//     defer compiled.deinit();
//     assert(compiled.re_code == null);
//     assert(compiled.errornumber == 106);
//     const expected = "missing terminating ] for character class";
//     assert(std.mem.eql(u8, expected, compiled.errormessage().?));
// }

test "return a list with zero matches" {
    const compiled = compile("foo");
    defer compiled.deinit();
    const matches = try compiled.findall("bar");
    assert(Matches_equal(matches, zero_matches));
}

// test "return a list with all matches" {
//     const compiled = compile(".*");
//     defer compiled.deinit();
//     _ = try compiled.findall("balalaika");
// }

// test "am I crazy?" {
//     assert(mem.eql(Matches, zero_matches, zero_matches));
// }

// test "print the cImported pcre2 struct" {
//     const ti = @typeInfo(Pattern).Struct;
//     // std.debug.warn("pcre2={}\n", .{ti});
//     inline for (ti.fields) |f| {
//         std.debug.print("\n", .{});
//         std.debug.warn("{} ", .{f});
//     }
// }
