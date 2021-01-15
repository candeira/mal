const std = @import("std");
const assert = std.debug.assert;

pub fn Pair(comptime T: type) type {
    return [2]T;
}

// this is not really general code
// but ok while it works for testing re.zig
// maybe name the functions more narrowly
// so it's clear that the defeated claim is not as ambitious
// as the original intent was
pub fn assert_equal_slices(comptime T: type, sliceA: []T, sliceB: []T) !void {
    assert(sliceA.len == sliceB.len);
    while (izip(T, sliceA, sliceB)) |pair| {
        assert(mem.eql(T, pair[0], pair[1]));
    }
}

pub fn izip(comptime T: type, sliceA: []T, sliceB: []T) ?Pair(T) {
    // TODO: figure out how to pass the default element as an option
    // or something similar, so we can pair as the longer sequence
    // for now we'll pair as the shorter sequence
    var result_len = std.math.min(sliceA.len, sliceB.len);
}

test "assert zero length slices are equal" {
    const a = "";
    const b = "";
    try assert_equal_slices(u8, a[0..], b[0..]);
}
