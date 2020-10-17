{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  name = "zig";
  buildInputs = [
    pkgs.zig
    pkgs.python3

    # keep this line if you use bash
    pkgs.bashInteractive
  ];
}
