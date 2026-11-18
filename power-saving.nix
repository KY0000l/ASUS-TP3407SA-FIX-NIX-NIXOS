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
    CPU_SCALING_GOVERNOR_ON_AC = "powersave";
    CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

    CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
    CPU_ENERGY_PERF_POLICY_ON_BAT = "balance_power";

    CPU_MIN_PERF_ON_AC = 0;
    CPU_MAX_PERF_ON_AC = 100;
    CPU_MAX_PERF_ON_BAT = 100;

    CPU_BOOST_ON_AC = 1;
    CPU_BOOST_ON_BAT = 0;
    CPU_HWP_DYN_BOOST_ON_AC = 1;
    CPU_HWP_DYN_BOOST_ON_BAT = 0;

    PLATFORM_PROFILE_ON_AC = "performance";
    PLATFORM_PROFILE_ON_BAT = "low-power";

    PCIE_ASPM_ON_AC = "default";
    PCIE_ASPM_ON_BAT = "powersupersave";

    RUNTIME_PM_ON_AC = "on";
    RUNTIME_PM_ON_BAT = "auto";
  };
}
