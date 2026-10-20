{ config, lib, pkgs, ... }:

let
  # The kernel asks for TAS2XXX10A4.bin, linux-firmware ships TAS2XXX10A41.bin.
  # Handles both plain and zstd-compressed linux-firmware packages.
  tas2781Fix = pkgs.runCommand "tas2781-fw-10a4" { } ''
    src=${pkgs.linux-firmware}/lib/firmware
    mkdir -p $out/lib/firmware
    if [ -e "$src/TAS2XXX10A41.bin" ]; then
      cp "$src/TAS2XXX10A41.bin" $out/lib/firmware/TAS2XXX10A4.bin
    elif [ -e "$src/TAS2XXX10A41.bin.zst" ]; then
      cp "$src/TAS2XXX10A41.bin.zst" $out/lib/firmware/TAS2XXX10A4.bin.zst
    else
      echo "TAS2XXX10A41 firmware not found in linux-firmware" >&2
      exit 1
    fi
  '';
in
lib.mkIf config.hardware.asusfix.speaker.enable {
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ tas2781Fix ];
}
