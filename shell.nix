with (import <nixpkgs> {});
mkShell {
  buildInputs = [
    elixir
    stdenv
    libsodium
    gmp
    nodejs_20
    dart-sass
  ];
}
