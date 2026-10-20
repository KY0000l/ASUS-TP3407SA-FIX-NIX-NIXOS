# ASUS-TP3407SA-FIX-NIX-NIXOS

The primary code in this repo (.nix .py .rs etc..) is licensed under the gplv3, the proprietary blob in firmware/ is licensed under the Intel Simplified Software License and is being disclosed as such in accordance with the license.

My ASUS Vivobook is poorly supported on NixOS, I made these collections of changes and thought others may enjoy them as well.
What options (when I add support)
- NPU support
- Speaker amplifier fix
- Tablet mode/auto rotation/Lid detection
- Adds xe driver to initrd to stop plymouth DRM conflicts
- Changes power saving behavior
hardware.asusfix.enableALLchanges = true; can be used to enable all of these changes, additionally it enables/requires the use of unfree blobs, if you are okay with this, enable this option.
