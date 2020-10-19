const Str = @Import("types.zip").Str;
const cStr = @Import("types.zip").cStr;

const token_match: cStr =
    \\[\s,]*(~@|[\[\]{}()'`~^@]|"(?:\\.|[^\\"])*"?|;.*|[^\s\[\]{}('"`,;)]*)
;

pub const Reader = struct {};

pub fn read_str() void {}

pub fn read_form() void {}

pub fn tokenize() void {}
