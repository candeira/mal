{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  name = "zig";
  buildInputs = [
    pkgs.zig
    pkgs.python3
    pkgs.libc
    pkgs.pcre2
    pkgs.readline

    # keep this line if you use bash
    pkgs.bashInteractive
  ];
}
