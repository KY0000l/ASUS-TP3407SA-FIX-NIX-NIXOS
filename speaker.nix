{ config, lib, pkgs, ... }:

let
  # Speaker amp fix. Source lives in ./sound-fix (see sound-fix/NOTICE for its origin).
  sound-fix = pkgs.rustPlatform.buildRustPackage {
    pname = "asus-sound-fix";
    version = "0.1.3";

    src = lib.cleanSource ./sound-fix;
    cargoLock.lockFile = ./sound-fix/Cargo.lock;

    meta = {
      description = "TAS2781 speaker amplifier setup for the ASUS Vivobook S14 Flip TP3407SA";
      license = lib.licenses.gpl3Only;
      mainProgram = "sound-fix";
      platforms = [ "x86_64-linux" ];
    };
  };

  # Wait (up to 30 s) for the sound card instead of looping forever.
  waitForSound = pkgs.writeShellScript "wait-for-sound" ''
    for _ in $(seq 1 60); do
      [ -e /dev/snd/controlC0 ] && exit 0
      sleep 0.5
    done
    echo "sound card did not appear" >&2
    exit 1
  '';
in
lib.mkIf config.hardware.asusfix.speaker.enable {
  # The tool talks to the amplifiers through /dev/i2c-*.
  hardware.i2c.enable = true;

  systemd.services.asus-sound-fix = {
    description = "ASUS Vivobook S14 Flip TP3407SA speaker fix";
    wantedBy = [ "multi-user.target" ];
    after = [ "sound.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = waitForSound;
      ExecStart = "${sound-fix}/bin/sound-fix";
    };
  };
}
