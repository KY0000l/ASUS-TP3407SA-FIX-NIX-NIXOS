{ config, lib, ... }:

lib.mkIf config.hardware.asusfix.powerSaving.enable {
  boot.kernelParams = [ "pcie_aspm.policy=powersave" ];
  boot.kernel.sysctl."kernel.nmi_watchdog" = 0;

  powerManagement.enable = true;
  # mkDefault so you can swap in TLP instead (don't run both).
  services.power-profiles-daemon.enable = lib.mkDefault true;
  services.thermald.enable = true;
  services.upower.enable = true;
  networking.networkmanager.wifi.powersave = true;
}
