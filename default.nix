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
    ./fnlock.nix
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

    # A preference rather than a fix, so it is not part of enableALLchanges.
    fnlock.multimedia.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Make the top row act as multimedia keys by default (Fn lock off) by
        passing asus_wmi.fnlock_default=0. When false, nothing is passed and
        the kernel default (F1-F12 as function keys) applies.
      '';
    };
  };

  config = lib.mkIf cfg.enableALLchanges {
    nixpkgs.config.allowUnfree = lib.mkDefault true;
    # Lunar Lake needs a recent kernel for xe, ISH and the NPU.
    boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
  };
}
