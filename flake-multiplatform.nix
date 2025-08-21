{
  description = "Claude Session Manager - Multi-platform TypeScript/Deno CLI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ 
      "x86_64-linux" 
      "aarch64-linux"
      "x86_64-darwin" 
      "aarch64-darwin" 
    ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Map system to pre-built binary
        binaryMap = {
          "x86_64-linux" = ./binaries/claude-manager-linux-x64;
          "aarch64-linux" = ./binaries/claude-manager-linux-arm64;
          "x86_64-darwin" = ./binaries/claude-manager-macos-x64;
          "aarch64-darwin" = ./binaries/claude-manager-macos-arm64;
        };
        
        # Check if we have a pre-built binary for this system
        hasBinary = builtins.hasAttr system binaryMap;
        
        # Pre-built binary package
        claude-manager-binary = pkgs.stdenv.mkDerivation rec {
          pname = "claude-session-manager";
          version = "1.0.0";
          
          src = if hasBinary then binaryMap.${system} else null;
          
          dontUnpack = true;
          dontBuild = true;
          
          buildInputs = with pkgs; [
            tmux
            fzf
            gum
            zoxide
            jq
          ];
          
          nativeBuildInputs = with pkgs; [ makeWrapper ];
          
          installPhase = if hasBinary then ''
            mkdir -p $out/bin
            cp ${src} $out/bin/claude-manager
            chmod +x $out/bin/claude-manager
            
            wrapProgram $out/bin/claude-manager \
              --prefix PATH : ${pkgs.lib.makeBinPath buildInputs}
          '' else ''
            mkdir -p $out/bin
            echo "#!/usr/bin/env bash" > $out/bin/claude-manager
            echo "echo 'Pre-built binary not available for ${system}'" >> $out/bin/claude-manager
            echo "echo 'Please build from source using: nix build .#claude-session-manager-source'" >> $out/bin/claude-manager
            chmod +x $out/bin/claude-manager
          '';
          
          meta = with pkgs.lib; {
            description = "TypeScript/Deno session manager for Claude Code";
            homepage = "https://github.com/PittampalliOrg/claude-session-manager";
            license = licenses.mit;
            platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            mainProgram = "claude-manager";
          };
        };
        
        # Build from source package
        claude-manager-source = pkgs.stdenv.mkDerivation rec {
          pname = "claude-session-manager-source";
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
            export HOME=$TMPDIR
            cp -r $src/*.ts $src/deno.json .
            
            # Compile for the current platform
            deno compile \
              --allow-all \
              --output claude-manager \
              claude-session-manager.ts
          '';
          
          installPhase = ''
            mkdir -p $out/bin
            cp claude-manager $out/bin/
            
            wrapProgram $out/bin/claude-manager \
              --prefix PATH : ${pkgs.lib.makeBinPath buildInputs}
          '';
          
          meta = with pkgs.lib; {
            description = "TypeScript/Deno session manager for Claude Code (built from source)";
            homepage = "https://github.com/PittampalliOrg/claude-session-manager";
            license = licenses.mit;
            platforms = platforms.all;
            mainProgram = "claude-manager";
          };
        };
      in
      {
        packages = {
          default = if hasBinary then claude-manager-binary else claude-manager-source;
          claude-session-manager = if hasBinary then claude-manager-binary else claude-manager-source;
          claude-session-manager-binary = claude-manager-binary;
          claude-session-manager-source = claude-manager-source;
        };
        
        apps.default = flake-utils.lib.mkApp {
          drv = if hasBinary then claude-manager-binary else claude-manager-source;
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
            echo "Platform: ${system}"
            echo ""
            echo "Commands available:"
            echo "  deno task cli     - Run the CLI"
            echo "  deno task test    - Run test setup"
            echo "  deno task compile - Compile to binary"
            echo ""
            echo "Cross-compilation targets:"
            echo "  deno compile --target x86_64-unknown-linux-gnu"
            echo "  deno compile --target aarch64-unknown-linux-gnu"
            echo "  deno compile --target x86_64-apple-darwin"
            echo "  deno compile --target aarch64-apple-darwin"
            echo "  deno compile --target x86_64-pc-windows-msvc"
            echo ""
          '';
        };
      });
}