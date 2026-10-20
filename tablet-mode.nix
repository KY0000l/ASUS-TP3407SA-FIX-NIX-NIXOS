{ config, lib, pkgs, ... }:

let
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.evdev ]);

  # Model-specific ISH firmware. The kernel requests
  #   intel/ish/ish_lnlm_<vendor crc32>_<product name crc32>.bin
  #   vendor "ASUSTeK COMPUTER INC."                 = ef534c00
  #   name   "ASUS Vivobook 14 Flip TP3407SA_TP3407SA" = a5460864
  ishFirmware = pkgs.runCommand "ish-firmware" { } ''
    mkdir -p $out/intel/ish
    cp ${./firmware/ish/ish_lnlm_ef534c00_a5460864.bin} \
       $out/intel/ish/ish_lnlm_ef534c00_a5460864.bin
  '';
in
lib.mkIf config.hardware.asusfix.tabletMode.enable {
  boot.extraModprobeConfig = ''
    options asus_nb_wmi tablet_mode_sw=2
  '';

  # The ISH probes in the initrd, before the real root is mounted, so the
  # firmware has to ship inside the initrd. That needs the systemd initrd.
  boot.initrd.systemd.enable = lib.mkDefault true;
  boot.initrd.systemd.contents."/etc/ish-firmware".source = ishFirmware;
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
      ExecStart = "${pythonEnv}/bin/python3 ${./hinge-tablet-mode.py}";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
}
