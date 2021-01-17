/// re.zig
///
/// implement a limited subset of the Python regular expressions ("re") module API
/// matcher = re.compile("lala")
/// matcher.findall("balaladamepanlala")
/// ["lala", "lala"]
///
/// (c) 2020 Javier Candeira
/// Released under both MIT and Apache 2 licenses
/// TODO: figure out better license language

// TODO: figure out better logging than debug.warn()

// // IMPORTS
const std = @import("std");
const allocator = std.heap.c_allocator;
const assert = std.debug.assert;
const mem = std.mem;

// TODO: Figure out how to do import so we don't have to use the _8 names for functions and types
const pcre2 = @cImport({
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
});

// // TYPES and singleton values

// // String types used for wrapping the pcre2 regular expression library:

// These are runtime types, not comptime types.
// When writing tests, ensure the values passed are not comptime
// because the slices will have different types in either case!
//
// https://ziglang.org/download/0.6.0/release-notes.html#Slicing-with-Comptime-Indexes

// Zig strings are immutable slices of utf8
// String literals are zero-terminated, but we don't want that:
// - pcre2 already uses pointer, length for inputs and outputs.
// - our regex match results will be backed by the subject string,
//   so we can't zero terminate them.
const Str = []const u8;

// A re.empty_string is a zero length slice of u8
// and we need to initialise it as runtime (see above)
// TODO: make it a runtime-generated const, because we never want it assigned to
const empty_string: Str = emptyString();

fn emptyString() Str {
    return &[0]u8{};
}

// A re.Matches type is a list of match results.
// Its Zig type is a slice of Strs ([][]const u8, once dealiased)
// Matches storage is as follows:
// - list of match results (outer slice): TODO: heap or stack?
// - each match result Str: backed by the subject string's buffer
const Matches = []Str;

// re.zero_matches is an empty slice of Strs,
// And we need to initialise it as runtime! (see above)
// TODO: make it a runtime-generated const, because we never want it assigned to
var zero_matches: Matches = zeroMatches();

fn zeroMatches() Matches {
    return &[0]Str{};
}

// TODO: move all pcre2 imported types to their own struct
// TODO: figure out types off pcre2.h instead of from compiler errors
const pcre2_size = pcre2.PCRE2_SIZE;
// can't find the values off pcre2.h;
// reverse engineering from compiler errors
const pcre2_errornumber_t = c_int;
const pcre2_erroroffset_t = usize;
const pcre2_errorlength_t = c_int;
const pcre2_errorbuffer_t = [256:0]u8;
const pcre2_match_data_t = pcre2.struct_pcre2_real_match_data_8;

// an ovector or output vector is an array of (*start, *end) pointers into the subject string
const pcre2_Ovector = [*c]usize;
// we'll be reading them by casting them to a Zig array of structs
// for cleaner iteration: let the compiler make the assembler neat,
// but we will make the human-readable code neat
const pcre2_Match = extern struct {
    _start: *c,
    _end: *c,

    fn zigMatch(self: pcre2_Match) Str {}
};

const pcre2_Matches = [*]pcre2_Match;

// // UTIL (TODO: move eventually to some util.zig grab bag)

const Sign = enum(i2) {
    Negative = -1,
    Zero = 0,
    Positive = 1,
};

fn sign(x: c_int) Sign {
    if (x == 0) {
        return .Zero;
    }
    const bits = @bitCast(u32, x);
    if (bits >> 31 != 0) {
        return .Negative;
    } else {
        return .Positive;
    }
}

// // ERRORS!

// see  http://pcre.org/current/doc/html/pcre2unicode.html
// also https://github.com/PCRE/pcre2/blob/master/src/pcre2.h.in
// and http://pcre.org/current/doc/html/pcre2api.html
//
// TODO: make exhaustive.
//
// It would be also nice to have errors be tagged unions so the messages
// from "positive errors" can be converted to payloads of error enums
// (as per proposal https://github.com/ziglang/zig/issues/2647)

// nicer than "PCRE2Error"
const RegexError = error{
    BadPattern, // positive error thrown by PCRE2 while attempting to compile a pattern
    VectorOffsetsErrorWhileAttemptingMatch, // zero error while matching
    UTFErrorWhileMatchingTODOListAllErrors, // negative error while matching
};

// // PCRE2 WRAPPER AND re MODULE IMPLMEMENTATION

// TODO: organise the public part of the library

// TODO: figure out the documentation convention, make these into doc comments

/// Return a compiled pattern from a Zig string or slice
/// Compiled RE code will be in C heap
/// But Pattern code lives in the stack
/// Any error during pattern compilation will be stored
/// in the Pattern object, and can be inspected later,
/// will trigger when people try to match/find
pub fn compile(pattern: Str) Pattern {
    return Pattern.init(pattern);
}

/// A structure for:
/// - holding compiled regex patterns,
/// - using these compiled patterns to match subject strings
/// - returning match results as slices into the subject strings
///
/// Initialise only with re.compile(pattern)
///
/// TODO: Figure out lifetime and memory ownership
/// TODO: Figure out a convention for private module namespaces
const Pattern = struct {
    pattern: Str,
    re_code: ?*pcre2.pcre2_code_8 = null,
    errornumber: pcre2_errornumber_t = 0,
    erroroffset: pcre2_erroroffset_t = 0,
    errorbuffer: pcre2_errorbuffer_t = undefined,
    errorlength: pcre2_errorlength_t = 0,
    match_data: ?*pcre2_match_data_t = null,

    /// Returns the latest pcre2 error as a re.zig Str.
    /// This is because pcre2 errors contain much more information
    /// than can be expressed as Zig error sets.
    pub fn errormessage(self: Pattern) Str {
        if (self.re_code == null) {
            const end = @bitCast(u32, self.errorlength);
            return self.errorbuffer[0..end];
        } else {
            return empty_string;
        }
    }

    /// Initialises a Pattern object from a Zig string
    /// TODO: I think we don't want to make this a public interface
    /// TODO: because we want re.compile() to be able to be generic:
    /// TODO: - re.zig Str
    /// TODO: - comptime Str
    /// TODO: - etc.
    pub fn init(pattern: Str) Pattern {
        var errornumber: pcre2_errornumber_t = 0;
        var erroroffset: pcre2_erroroffset_t = 0;

        // the compiled pcre2 code object is an optional pointer
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
            // if there's a compilation error, find and store the error message
            var errorbuffer = @ptrCast([*]u8, &matcher.errorbuffer);
            matcher.errorlength = pcre2.pcre2_get_error_message_8(
                errornumber,
                errorbuffer,
                @sizeOf(pcre2_errorbuffer_t),
            );
        } else {
            // If there's no compilation error, create the match_data structure and get a pointer.
            // As far as Zig knows, *pcre2.bar pcre2.foo() functions could return null pointers,
            // so the return type Zig sees from C optional pointer ?*pcre2.bar and not *pcre2.bar...
            matcher.match_data = pcre2.pcre2_match_data_create_from_pattern_8(re_code, null);
            // there should be no reason we get a null, since the re_code is a valid pointer
            if (matcher.match_data == null) unreachable;
        }

        return matcher;
    }

    pub fn deinit(self: Pattern) void {
        if (self.re_code != null)
            pcre2.pcre2_code_free_8(self.re_code);
        if (self.match_data != null)
            pcre2.pcre2_match_data_free_8(self.match_data);
    }

    // Allocates an array of matches, backed by the matching string.
    // Caller becomes owner of memory.
    // results live in C Heap because life's too short
    // TODO: pass an Allocator so we can do things like passing GPA backed by C heap allocator
    //     : and look for memory leaks during tests, and use the C heap for actual production code
    //     : of course the allocator would be passed during initialisation,
    //     : because match_data is variable size and producing during initialisation
    pub fn findall(self: Pattern, subject: Str) !Matches {
        if (self.match_data == null) {
            return error.BadPattern;
        }

        const first_match_code = pcre2.pcre2_match_8(
            self.re_code,
            @ptrCast([*]const u8, subject),
            subject.len, // This is in code units, not characters
            0, // Offset at which to start matching, in code units
            0, // Option bits
            self.match_data,
            null, // Points to a match context, or is NULL
        );

        // The return value of pcre2_match() is particular.
        // Comments in branches of switch are direct quotations from documentation:
        // http://pcre.org/current/doc/html/pcre2_match.html

        var captures: c_int = switch (sign(first_match_code)) {
            .Negative => {
                // "no match and other errors"
                if (first_match_code == pcre2.PCRE2_ERROR_NOMATCH) {
                    return zero_matches;
                }
                const template = "re.findall(): pcre2_match() returns {}. TODO: match error codes to zig error values.\n";
                // std.debug.warn(template, .{first_match_code});

                return error.UTF;
            },
            .Zero => {
                // from https://github.com/PCRE/pcre2/src/pcre2demo.c:
                //
                //     /* The output vector wasn't big enough. This should not happen, because we used
                //     pcre2_match_data_create_from_pattern() above. */
                //
                // there's example code there too, seems this is for pathological patterns:
                //
                //     /* We must guard against patterns such as /(?=.\K)/ that use \K in an assertion
                //     to set the start of a match later than its end. In this demonstration program,
                //     we just detect this case and give up. */
                //
                // std.debug.warn("re.findall(): pcre2_match() returns zero: 'the vector of offsets is too small'\n", .{});
                return error.VectorOffsetsErrorWhileAttemptingMatch;
            },
            .Positive => first_match_code - 1,
            // "one more than the highest numbered capturing pair that has been set"
            // "(for example, 1 if there are no captures)"
        };

        // std.debug.warn("\n\nre.findall(): pcre2_match() has captured {} regions\n\n", .{captures});

        // subject is a []const u8, the target  of the regex;
        // ovector is a collection of matches as a an array of start, end offsets into the subject;

        var ovector: pcre2_Ovector = pcre2.pcre2_get_ovector_pointer_8(self.match_data);
        try self._guardAgainstReverseMatches(ovector);

        const n_captures = @intCast(usize, captures);
        var matches: Matches = try allocator.alloc(Str, n_captures);
        for (matches) |*match, i| {
            const start = ovector[2 * i];
            const end = ovector[(2 * i) + 1];
            match.ptr = subject.ptr + start;
            match.len = end - start;
        }
        // matches is c_heap-allocated, now owned by caller
        return matches;

        // but we have more than one match, dammit
        // so we must keep going until we have zero captures
    }

    pub fn _setError(self: Pattern, message: Str) void {
        // const len = message.len;
        // self.errorlength.* = len;
        // &self.errorbuffer.* = message;
        // mem.copy(u8, self.errorbuffer[0..len], message[0..len]);
    }

    pub fn _guardAgainstReverseMatches(self: Pattern, ovector: pcre2_Ovector) !void {
        // /* We must guard against patterns such as /(?=.\K)/ that use \K in an assertion
        //     to set the start of a match later than its end. In this demonstration program,
        // we just detect this case and give up. */

        //     if (ovector[0] > ovector[1])
        //     {
        //         printf("\\K was used in an assertion to set the match start after its end.\n"
        //                    "From end to start the match was: %.*s\n", (int)(ovector[0] - ovector[1]),
        //                (char *)(subject + ovector[1]));
        //         printf("Run abandoned\n");
        //         pcre2_match_data_free(match_data);
        //         pcre2_code_free(re);
        //         return 1;
        // }
    }
};

// TESTS
//

// move to util.zig eventually
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

// move to util.zig eventually
fn Matches_equal(a: Matches, b: Matches) bool {
    if (a.len != b.len) {
        return false;
    }
    for (a) |item_a, i| {
        var item_b = b[i];
        if (!Str_equal(item_a, item_b)) {
            return false;
        }
    }
    return true;
}

fn Matches_warn(matches: Matches) void {
    std.debug.warn("{}: [", .{matches.len});
    for (matches) |item, i| {
        std.debug.warn("'{}'", .{item});
        if ((i + 1) < matches.len) {
            std.debug.warn(", ", .{});
        }
    }
    std.debug.warn("]\n", .{});
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
    assert(Str_equal(compiled.errormessage(), empty_string));
}

test "return a Pattern containing an error" {
    const compiled = compile("[");
    defer compiled.deinit();
    assert(compiled.re_code == null);
    assert(compiled.errornumber == 106);
    const expected = "missing terminating ] for character class";
    assert(std.mem.eql(u8, expected, compiled.errormessage()));
}

test "return a list with zero matches" {
    const compiled = compile("foo");
    defer compiled.deinit();
    const matches = try compiled.findall("bar");
    defer allocator.free(matches);
    assert(Matches_equal(matches, zero_matches));
}

const patterns = &[_]Str{ "(a)", "(.*)", "((.*)*)" };
const subjects = &[_]Str{ "", "patata", "dame", "wot" };

test "run patterns over subjects" {
    // std.debug.warn("\n", .{});
    for (patterns) |pattern| {
        const c = compile(pattern);
        for (subjects) |subject| {
            const results = try c.findall(subject);
            // Matches_warn(results);
        }
    }
}

test "return a list with a single capture encompassing the whole string" {
    // we make both regex and subject runtime slices
    var pattern: Str = &[_]u8{ '(', 'a', ')' };
    var subject: Str = &[_]u8{'a'};
    var expected: Matches = &[_]Str{subject};
    // const compiled = compile("((.*)*)");
    const compiled = compile(pattern);
    defer compiled.deinit();
    var result = try compiled.findall(subject);
    defer allocator.free(result);
    assert(Str_equal(compiled.errormessage(), empty_string));
    assert(Matches_equal(expected, result));
}

test "matches comptime subjects with runtime regex" {}

test "matches runtime subjects with comptime regex" {}

test "matches runtime subjects with runtime regex" {}

test "matches comptime subjects with comptime regex" {}

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
