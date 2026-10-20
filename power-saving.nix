{ config, lib, ... }:

lib.mkIf config.hardware.asusfix.powerSaving.enable {
  boot.kernelParams = [ "pcie_aspm.policy=powersave" ];
  boot.kernel.sysctl."kernel.nmi_watchdog" = 0;

  powerManagement.enable = true;
  networking.networkmanager.wifi.powersave = true;

  services.tlp.enable = lib.mkDefault true;
  services.power-profiles-daemon.enable = lib.mkOverride 900 false;

  # Battery-only tuning. Every value is a default, so you can override single
  # settings with services.tlp.settings.<NAME> = ...;
  services.tlp.settings = lib.mapAttrs (_: lib.mkDefault) {
    CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
    CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
    CPU_BOOST_ON_BAT = 0;
    CPU_HWP_DYN_BOOST_ON_BAT = 0; # no short-term boost on battery
    CPU_MAX_PERF_ON_BAT = 80;     # cap max performance percentage
  };
}
