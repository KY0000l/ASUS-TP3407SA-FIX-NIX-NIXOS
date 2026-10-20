# ASUS-TP3407SA-FIX-NIX-NIXOS

NixOS module with fixes for the **ASUS Vivobook 14 Flip TP3407SA** (Intel Lunar Lake).

My Vivobook is poorly supported on NixOS, so I collected my changes into a module that others can use too. Every fix is its own switch, so you can enable only what you want.

# PLEASE AT LEAST READ THIS
 This project is designed for maximum compatibility and nothing else!
 Changes when all modules are enabled include
- Systemd initrd (is harmless, unless you hate systemd)
- Modified kernel parameters and initrd
- Directly addressing memory over i2c
- Enabling unfree software and injecting binary blobs on boot
- Forcing the latest linux kernel (you probably have this one on anyways)

## About the blob
The binary blob found in firmware/ was extracted from the windows driver. I extracted it myself. If you do not trust it you can extract your own .bin or potentially source one from elsewhere on the internet and use that. (fork the repo and swap the files)

## Licensing and credits

The primary code in this repo (`.nix`, `.py`, etc.) is licensed under the GPLv3 (see `LICENSE`).
The proprietary blob in `firmware/` is licensed under the Intel Simplified Software License (see `LICENSE.intel`) and is disclosed as such in accordance with that license. It is only used by `tabletMode`.

## What it fixes

| Option | What it does |
| --- | --- |
| `hardware.asusfix.npu.enable` | Intel NPU driver and firmware |
| `hardware.asusfix.speaker.enable` | Speaker amplifier (TAS2781) fix, using the Rust tool in `sound-fix/` |
| `hardware.asusfix.fnlock.multimedia.enable` | Makes fnlock multimedia mode the default using `"asus_wmi.fnlock_default=0"` |
| `hardware.asusfix.tabletMode.enable` | Tablet mode, auto-rotation and lid/hinge detection |
| `hardware.asusfix.initrdXe.enable` | Loads the `xe` driver in the initrd to stop Plymouth DRM conflicts |
| `hardware.asusfix.powerSaving.enable` | Power saving tweaks (ASPM, thermald, power-profiles-daemon, Wi-Fi powersave) |
| `hardware.asusfix.graphics.enable` | Intel GPU acceleration (media driver, compute runtime, VPL) |
| `hardware.asusfix.enableALLchanges` | Turns on **all** of the above |

Each individual option defaults to the value of `enableALLchanges`, so you can enable everything and opt out of single pieces.

> **Unfree software:** `enableALLchanges = true` also sets `nixpkgs.config.allowUnfree = true` (as a default), because the NPU and GPU firmware are unfree redistributable firmware. If you are okay with that, enable it. If not, enable only the options you want and manage `allowUnfree` yourself. The speaker fix does not need unfree software.

## Usage (flakes)

Add this repo as an input and import its module in your host:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    asus-tp3407sa.url = "github:KY0000l/ASUS-TP3407SA-FIX-NIX-NIXOS";
  };

  outputs = { nixpkgs, asus-tp3407sa, ... }: {
    nixosConfigurations.my-vivobook = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        asus-tp3407sa.nixosModules.default   # <- the module
        ./configuration.nix
      ];
    };
  };
}
```

Then turn on what you want in `configuration.nix`:

```nix
# Everything:
hardware.asusfix.enableALLchanges = true;
```

```nix
# Or pick individual fixes:
hardware.asusfix = {
  npu.enable = true;
  speaker.enable = true;
  tabletMode.enable = true;
  initrdXe.enable = true;
  powerSaving.enable = false;
};
```

```nix
# Or everything except one piece:
hardware.asusfix = {
  enableALLchanges = true;
  powerSaving.enable = false;   # e.g. you prefer TLP
};
```

Rebuild with `sudo nixos-rebuild switch --flake .#my-vivobook`.

The module uses your own `nixpkgs`, so you don't need `inputs.nixpkgs.follows`.

## Usage (without flakes)

```nix
# configuration.nix
{
  imports = [
    "${builtins.fetchGit {
      url = "https://github.com/KY0000l/ASUS-TP3407SA-FIX-NIX-NIXOS";
      # rev = "<commit hash>";  # pin this for reproducibility
    }}"
  ];

  hardware.asusfix.enableALLchanges = true;
}
```

## Notes

- **Speaker fix writes to the amplifier chips directly.** It runs at boot and resume as a oneshot service (`asus-sound-fix.service`) and sends a fixed register sequence to the two TAS2781 chips over I2C, bypassing the kernel driver. It is made for the TP3407SA board; don't enable it on other models unless you know they match. Check it with `systemctl status asus-sound-fix`.
- **Tablet mode switches your initrd to systemd.** The ISH firmware has to be inside the initrd, so `tabletMode.enable` sets `boot.initrd.systemd.enable = lib.mkDefault true`. If your LUKS setup depends on the scripted initrd, check it before enabling.
- **Recent nixpkgs required.** `hardware.cpu.intel.npu.enable` only exists in recent nixpkgs; `nixos-unstable` is the safe choice.
- **Kernel.** `enableALLchanges` selects `linuxPackages_latest` (as a default) since Lunar Lake needs a recent kernel. Override it with `boot.kernelPackages` if you want.
- **Power profiles.** `power-profiles-daemon` is enabled by default under `powerSaving`. To use TLP instead, set `services.power-profiles-daemon.enable = false;` and enable TLP yourself. Don't run both.
