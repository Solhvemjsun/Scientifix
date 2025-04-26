{
  inputs = {
    dream2nix = {
      url = "github:nix-community/dream2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "nixpkgs"; # It's better to use the same commit as your NixOS system
  };

  outputs =
    {
      self,
      dream2nix,
      nixpkgs,
    }:
    let
      eachSystem = nixpkgs.lib.genAttrs [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
    in
    {
      packages = eachSystem (system: {
        default = dream2nix.lib.evalModules {
          packageSets.nixpkgs = nixpkgs.legacyPackages.${system};
          modules = [
            ./package.nix
            {
              paths.projectRoot = ./.;
              paths.projectRootFile = "flake.nix";
              paths.package = ./.;
            }
          ];
        };
      });
      devShells = eachSystem (system: {
        default =
          let
            pkgs = import nixpkgs {
              inherit system;
              config = {
                allowUnfree = true; # to use cudaPackages
              };
              overlays = [ ];
            };
            lib = pkgs.lib;
            myPkg = self.packages.${system}.default;
            python = myPkg.config.deps.python;
            myPython' = python.withPackages (
              ps: with ps; [
                myPkg.out

                # python packages are added here
                pip
              ]
            );
            myPython = myPython'.override (old: {
              ignoreCollisions = true;
            });
            libraries = with pkgs; [
              fontconfig
              libglvnd
              # needed by tensorflow
              cudaPackages_11.cudatoolkit
              cudaPackages_11.cudnn_8_9
            ];
          in
          pkgs.mkShell {
            packages = [
              myPython

              # non-python packages are added here
              pkgs.cowsay
            ];
            LD_LIBRARY_PATH = lib.concatStringsSep ":" [
              "/run/opengl-driver/lib" # gpu driver path of NixOS
              "${myPkg.config.pip.drvs.nvidia-cudnn-cu12.public.outPath}/${myPython.sitePackages}/nvidia/cudnn/lib"
              "${myPkg.config.pip.drvs.tensorflow.public.outPath}/${myPython.sitePackages}/tensorflow" # break break circular dependency with tensorflow-io-gcs-filesystem
              (lib.makeLibraryPath libraries)
            ];
          };
      });
    };
}
