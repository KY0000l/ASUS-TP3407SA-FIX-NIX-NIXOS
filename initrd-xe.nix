{ config, lib, ... }:

lib.mkIf config.hardware.asusfix.initrdXe.enable {
  boot.initrd.kernelModules = [ "xe" ];
}
