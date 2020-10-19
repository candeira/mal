const warn = std.debug.warn;
const std = @import("std");
const Str = @import("types.zig").Str;

fn READ(mal_input: Str) Str {
    return mal_input;
}

fn EVAL(mal_expr: Str) Str {
    return mal_expr;
}

fn PRINT(mal_result: Str) Str {
    return mal_result;
}

fn rep(input: Str) Str {
    var mal_expr = READ(input);
    var mal_result = EVAL(mal_expr);
    var mal_output = PRINT(mal_result);
    return mal_output;
}

pub fn main() !void {
    const stdout = std.io.getStdOut();
    const stdin = std.io.getStdIn();
    const prompt = "user> ";
    var line_buf: [255]u8 = undefined;
    while (true) {
        _ = try stdout.write("User> ");
        const line_len = try stdin.read(&line_buf);
        const output = rep(line_buf[0..line_len]);
        _ = try stdout.write(output);
    }
}
