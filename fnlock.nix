{ config, lib, ... }:

lib.mkIf config.hardware.asusfix.fnlock.multimedia.enable {
  # Fn lock off by default: F1-F12 act as multimedia keys (volume, brightness,
  # ...) and need Fn held for the real F-keys. Fn+Esc still toggles it.
  boot.kernelParams = [ "asus_wmi.fnlock_default=0" ];
}
