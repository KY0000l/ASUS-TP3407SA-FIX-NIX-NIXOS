{ config, lib, pkgs, ... }:

lib.mkIf config.hardware.asusfix.graphics.enable {
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-compute-runtime
      vpl-gpu-rt
    ];
  };
}
