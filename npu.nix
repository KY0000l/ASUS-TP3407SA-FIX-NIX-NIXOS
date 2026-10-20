{ config, lib, ... }:

lib.mkIf config.hardware.asusfix.npu.enable {
  hardware.cpu.intel.npu.enable = true;
  hardware.enableRedistributableFirmware = true;
}
