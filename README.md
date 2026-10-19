# ASUS-TP3407SA-FIX-NIX-NIXOS
My ASUS Vivobook is poorly supported on NixOS, I made these collections of changes and thought others may enjoy them as well.
What options (when I add support)
- NPU support
- Speaker amplifier fix
- Tablet mode/auto rotation/Lid detection
- Adds xe driver to initrd to stop plymouth DRM conflicts
- Changes power saving behavior
hardware.asusfix.enableALLchanges = true; can be used to enable all of these changes, additionally it enables/requires the use of unfree software, if you are okay with this, enable this option.
