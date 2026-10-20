{
  description = "NixOS fixes for the ASUS Vivobook 14 Flip TP3407SA";

  outputs = { self, ... }: {
    nixosModules.default = ./default.nix;
    nixosModules.asus-tp3407sa = self.nixosModules.default;
  };
}
