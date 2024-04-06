{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }: 
    flake-utils.lib.eachDefaultSystem (system:
      let 
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        circom-lsp = pkgs.rustPlatform.buildRustPackage {
          name = "circom-lsp";
          version = "0.1.3";
          src = pkgs.fetchFromGitHub {
            owner = "rubydusa";
            repo = "circom-lsp";
            rev = "v0.1.3";
            sha256 = "sha256-Y71qmeDUh6MwSlFrSnG+Nr/un5szTUo27+J/HphGr7M=";
          };
          cargoSha256 = "";
        };
      in
      with pkgs;
      {
        devShells.default = mkShell {
          buildInputs = [
            rust-bin.beta.latest.default
            rust-analyzer
            circom-lsp
            circom
          ];
        };
        
      }
    );
}
