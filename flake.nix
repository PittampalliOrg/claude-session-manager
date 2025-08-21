{
  description = "Claude Session Manager - TypeScript/Deno CLI for managing Claude Code sessions";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        claude-manager = pkgs.stdenv.mkDerivation rec {
          pname = "claude-session-manager";
          version = "1.0.0";
          
          src = ./.;
          
          nativeBuildInputs = with pkgs; [
            deno
            makeWrapper
          ];
          
          buildInputs = with pkgs; [
            tmux
            fzf
            gum
            zoxide
            jq
          ];
          
          buildPhase = ''
            # Create a temporary home for Deno cache
            export HOME=$TMPDIR
            
            # Copy source files
            cp -r $src/*.ts $src/deno.json .
            
            # Compile the binary
            deno compile \
              --allow-all \
              --output claude-manager \
              claude-session-manager.ts
          '';
          
          installPhase = ''
            mkdir -p $out/bin
            cp claude-manager $out/bin/
            
            # Wrap with runtime dependencies in PATH
            wrapProgram $out/bin/claude-manager \
              --prefix PATH : ${pkgs.lib.makeBinPath buildInputs}
          '';
          
          meta = with pkgs.lib; {
            description = "TypeScript/Deno session manager for Claude Code";
            homepage = "https://github.com/PittampalliOrg/claude-session-manager";
            license = licenses.mit;
            platforms = platforms.linux;
            mainProgram = "claude-manager";
          };
        };
      in
      {
        packages = {
          default = claude-manager;
          claude-session-manager = claude-manager;
        };
        
        apps.default = flake-utils.lib.mkApp {
          drv = claude-manager;
        };
        
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            deno
            tmux
            fzf
            gum
            zoxide
            jq
            gh
          ];
          
          shellHook = ''
            echo "Claude Session Manager Development Shell"
            echo "Commands available:"
            echo "  deno task cli     - Run the CLI"
            echo "  deno task test    - Run test setup"
            echo "  deno task compile - Compile to binary"
            echo ""
          '';
        };
      });
}