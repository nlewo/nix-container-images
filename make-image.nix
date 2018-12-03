{ pkgs }:

with pkgs.lib;

module:

let
  eval = evalModules {
    modules = [ module ] ++ [
      ./modules/fake.nix
      ./modules/system.nix
      ./modules/image.nix
      ./modules/nix-daemon.nix
    ] ++ (map (m: (pkgs.path + "/nixos/modules/") + m) [
      "/system/etc/etc.nix"
      "/config/users-groups.nix"
      "/misc/assertions.nix"
      "/config/shells-environment.nix"
      "/config/system-path.nix"
      "/config/system-environment.nix"
      "/programs/environment.nix"
      "/misc/ids.nix"
      "/programs/bash/bash.nix"
      "/security/pam.nix"
      "/security/wrappers/default.nix"
      "/programs/shadow.nix"
    ]);
    args = {
      inherit pkgs;
      utils = import (pkgs.path + /nixos/lib/utils.nix) pkgs;
    };
  };

  # We have to patch activation user scripts because they are creating
  # file in / while we only want to create files at container build time.
  activationScriptUsers = let
    userSpec = pkgs.lib.last (pkgs.lib.splitString " " eval.config.system.activationScripts.users.text);
    updateUsersGroupsPatched = pkgs.runCommand
      "update-users-groups-patched"
      { buildInputs = [pkgs.gnused]; }
      ''
        sed 's|/etc|etc|g;s|/var|var|g;s|nscd|true|g' ${(pkgs.path + /nixos/modules/config/update-users-groups.pl)} > $out
      '';
  in
    pkgs.runCommand "passwd-groups" { inherit userSpec; buildInputs = [ pkgs.jq ];} ''
      mkdir system
      cd system

      mkdir -p etc root $out
      
      sed 's|/home|home|g' $userSpec > ../userSpecPatched

      ${pkgs.perl}/bin/perl -w \
        -I${pkgs.perlPackages.FileSlurp}/lib/perl5/site_perl \
        -I${pkgs.perlPackages.JSON}/lib/perl5/site_perl \
        ${updateUsersGroupsPatched} ../userSpecPatched

       cp -r * $out/
    '';

  containerBuilder =
    if eval.config.nix.enable
    then pkgs.dockerTools.buildImageWithNixDb
    else pkgs.dockerTools.buildImage;


in containerBuilder {
  name = eval.config.image.name;
  tag = eval.config.image.tag;
  contents = [
    activationScriptUsers
    eval.config.system.path
    eval.config.system.build.etc ];
}
# For debugging purposes
// { config = eval.config; }