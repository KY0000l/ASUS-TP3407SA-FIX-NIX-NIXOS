{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.asusfix.tabletMode;

  # Source lives in ./hinge-tablet-mode (no crate dependencies).
  hingeTabletMode = pkgs.rustPlatform.buildRustPackage {
    pname = "hinge-tablet-mode";
    version = "0.1.0";
    src = lib.cleanSource ./hinge-tablet-mode;
    cargoLock.lockFile = ./hinge-tablet-mode/Cargo.lock;
    meta = {
      description = "Virtual SW_TABLET_MODE switch driven by the IIO hinge angle";
      license = lib.licenses.gpl3Only;
      mainProgram = "hinge-tablet-mode";
      platforms = [ "x86_64-linux" ];
    };
  };

  # Model-specific ISH firmware. The kernel requests
  #   intel/ish/ish_lnlm_<vendor crc32>_<product name crc32>.bin
  #   vendor "ASUSTeK COMPUTER INC."                 = ef534c00
  #   name   "ASUS Vivobook 14 Flip TP3407SA_TP3407SA" = a5460864
  ishFirmware = pkgs.runCommand "ish-firmware" { } ''
    mkdir -p $out/lib/firmware/intel/ish
    cp ${./firmware/ish_lnlm_ef534c00_a5460864.bin} \
       $out/lib/firmware/intel/ish/ish_lnlm_ef534c00_a5460864.bin
  '';
in
lib.mkIf cfg.enable {
  assertions = [{
    assertion = cfg.exitAngle < cfg.enterAngle;
    message = "hardware.asusfix.tabletMode.exitAngle must be lower than enterAngle.";
  }];

  boot.extraModprobeConfig = ''
    options asus_nb_wmi tablet_mode_sw=2
  '';

  # The ISH probes in the initrd, before the real root is mounted, so the
  # firmware has to ship inside the initrd. That needs the systemd initrd.
  boot.initrd.systemd.enable = lib.mkDefault true;
  boot.initrd.systemd.contents."/etc/ish-firmware".source = "${ishFirmware}/lib/firmware";
  boot.kernelParams = [ "firmware_class.path=/etc/ish-firmware" ];
  # Also available after boot, in case the ISH driver is reloaded.
  hardware.firmware = [ ishFirmware ];

  hardware.sensor.iio.enable = true;
  hardware.uinput.enable = true;

  # Publishes a virtual SW_TABLET_MODE switch from the IIO hinge angle
  # (the TP3407SA firmware doesn't provide one).
  systemd.services.hinge-tablet-mode = {
    description = "Tablet mode switch from IIO hinge angle";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udev-settle.service" ];
    serviceConfig = {
      ExecStart = lib.escapeShellArgs [
        "${hingeTabletMode}/bin/hinge-tablet-mode"
        "--enter" (toString cfg.enterAngle)
        "--exit" (toString cfg.exitAngle)
        "--poll-ms" (toString cfg.pollIntervalMs)
      ];
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
}
