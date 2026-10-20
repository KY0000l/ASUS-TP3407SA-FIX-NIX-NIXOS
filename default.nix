{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.asusfix;

  # Every individual switch defaults to whatever enableALLchanges is,
  # so you can turn everything on and then opt out of single pieces.
  feature = description: lib.mkOption {
    type = lib.types.bool;
    default = cfg.enableALLchanges;
    defaultText = lib.literalExpression "config.hardware.asusfix.enableALLchanges";
    inherit description;
  };
in
{
  imports = [
    ./graphics.nix
    ./initrd-xe.nix
    ./npu.nix
    ./power-saving.nix
    ./speaker.nix
    ./tablet-mode.nix
  ];

  options.hardware.asusfix = {
    enableALLchanges = lib.mkEnableOption ''
      every fix in this module. This also sets nixpkgs.config.allowUnfree
      (as a default) because the firmware and NPU driver are unfree.
      Only enable it if you are okay with that
    '';

    npu.enable          = feature "Intel NPU driver and firmware.";
    speaker.enable      = feature "Speaker amplifier (TAS2781) fix, using the tool in sound-fix/.";
    tabletMode.enable   = feature "Tablet mode, auto-rotation and lid/hinge detection (ISH firmware, IIO sensors, virtual tablet switch).";
    initrdXe.enable     = feature "Load the xe driver in the initrd to avoid Plymouth/DRM conflicts.";
    powerSaving.enable  = feature "Power saving tweaks (ASPM, thermald, power-profiles-daemon, Wi-Fi powersave).";
    graphics.enable     = feature "Intel GPU acceleration (media driver, compute runtime, VPL).";
  };

  config = lib.mkIf cfg.enableALLchanges {
    nixpkgs.config.allowUnfree = lib.mkDefault true;
    # Lunar Lake needs a recent kernel for xe, ISH and the NPU.
    boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
  };
}
