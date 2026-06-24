{
  description = "Mabau — static site";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];

      perSystem = { pkgs, ... }: {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            hugo
            git
            awscli2
            python3   # used by setup-aws.sh for JSON parsing
          ];

          shellHook = ''
            echo "Hugo $(hugo version | head -1)"
            echo "AWS CLI $(aws --version)"
          '';
        };

        packages.default = pkgs.stdenv.mkDerivation {
          pname = "site-mabau";
          version = "0.1.0";
          src = ./.;

          nativeBuildInputs = [ pkgs.hugo ];

          buildPhase = ''
            hugo --minify
          '';

          installPhase = ''
            cp -r public $out
          '';
        };
      };
    };
}
