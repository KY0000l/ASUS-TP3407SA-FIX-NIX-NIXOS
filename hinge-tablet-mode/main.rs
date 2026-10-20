//! Publishes a virtual SW_TABLET_MODE switch based on the hinge angle that the
//! kernel exposes through IIO. The TP3407SA firmware doesn't provide a switch.
//!
//! Hinge angles measured on the TP3407SA: ~103 normal, ~177 flat, 336 tent,
//! 360 tablet. Tablet mode turns on at or above `--enter` and off again at or
//! below `--exit`; the gap between the two is the hysteresis.

use std::env;
use std::ffi::{c_int, c_ulong};
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::mem::size_of;
use std::os::fd::AsRawFd;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::thread::sleep;
use std::time::Duration;

// ---- Defaults (override on the command line, or via the NixOS options) ----
const DEFAULT_ENTER: i64 = 300; // degrees: at or above this -> tablet mode
const DEFAULT_EXIT: i64 = 270; // degrees: at or below this -> laptop mode
const DEFAULT_POLL_MS: u64 = 200; // milliseconds between reads
const DEFAULT_IIO_DIR: &str = "/sys/bus/iio/devices";
const FIND_RETRY: Duration = Duration::from_secs(2);

// ---- Configuration ----------------------------------------------------------

#[derive(Debug, PartialEq)]
struct Config {
    enter: i64,
    exit: i64,
    poll: Duration,
    iio_dir: PathBuf,
}

const USAGE: &str = "\
Usage: hinge-tablet-mode [OPTIONS]

Options:
  --enter <deg>     angle at or above which tablet mode turns on  [default: 300]
  --exit <deg>      angle at or below which tablet mode turns off [default: 270]
  --poll-ms <ms>    time between hinge reads in milliseconds      [default: 200]
  --iio-dir <path>  IIO sysfs directory                           [default: /sys/bus/iio/devices]
  -h, --help        show this help

--exit must be lower than --enter; the gap prevents flickering around the threshold.";

enum Parsed {
    Run(Config),
    Help,
}

fn parse_args<I: Iterator<Item = String>>(mut args: I) -> Result<Parsed, String> {
    let mut cfg = Config {
        enter: DEFAULT_ENTER,
        exit: DEFAULT_EXIT,
        poll: Duration::from_millis(DEFAULT_POLL_MS),
        iio_dir: PathBuf::from(DEFAULT_IIO_DIR),
    };

    while let Some(arg) = args.next() {
        if arg == "-h" || arg == "--help" {
            return Ok(Parsed::Help);
        }
        // Accept both `--enter 300` and `--enter=300`.
        let (flag, inline) = match arg.split_once('=') {
            Some((f, v)) => (f.to_string(), Some(v.to_string())),
            None => (arg, None),
        };
        let mut value = |name: &str| -> Result<String, String> {
            inline
                .clone()
                .or_else(|| args.next())
                .ok_or_else(|| format!("{name} needs a value"))
        };
        match flag.as_str() {
            "--enter" => cfg.enter = parse_num(&value("--enter")?, "--enter")?,
            "--exit" => cfg.exit = parse_num(&value("--exit")?, "--exit")?,
            "--poll-ms" => {
                let ms: u64 = parse_num(&value("--poll-ms")?, "--poll-ms")?;
                if ms == 0 {
                    return Err("--poll-ms must be at least 1".into());
                }
                cfg.poll = Duration::from_millis(ms);
            }
            "--iio-dir" => cfg.iio_dir = PathBuf::from(value("--iio-dir")?),
            other => return Err(format!("unknown option: {other}")),
        }
    }

    if cfg.exit >= cfg.enter {
        return Err(format!(
            "--exit ({}) must be lower than --enter ({})",
            cfg.exit, cfg.enter
        ));
    }
    Ok(Parsed::Run(cfg))
}

fn parse_num<T: std::str::FromStr>(s: &str, name: &str) -> Result<T, String> {
    s.trim()
        .parse()
        .map_err(|_| format!("{name}: '{s}' is not a valid number"))
}

// ---- Hinge sensor -----------------------------------------------------------

fn read_trimmed(path: &Path) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| s.trim().to_string())
}

fn file_name_matches(path: &Path, f: impl Fn(&str) -> bool) -> bool {
    path.file_name().and_then(|n| n.to_str()).is_some_and(f)
}

/// Finds `in_anglN_raw` of the IIO device named "hinge" whose label is "hinge".
fn find_hinge(iio_dir: &Path) -> Option<PathBuf> {
    let mut devices: Vec<PathBuf> = fs::read_dir(iio_dir)
        .ok()?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| file_name_matches(p, |n| n.starts_with("iio:device")))
        .collect();
    devices.sort();

    for dev in devices {
        if read_trimmed(&dev.join("name")).as_deref() != Some("hinge") {
            continue;
        }
        let mut labels: Vec<PathBuf> = fs::read_dir(&dev)
            .ok()?
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .filter(|p| file_name_matches(p, |n| n.starts_with("in_angl") && n.ends_with("_label")))
            .collect();
        labels.sort();

        for label in labels {
            if read_trimmed(&label).as_deref() == Some("hinge") {
                let stem = label.file_name()?.to_str()?.strip_suffix("_label")?;
                return Some(dev.join(format!("{stem}_raw")));
            }
        }
    }
    None
}

fn read_angle(path: &Path) -> Option<i64> {
    read_trimmed(path)?.parse().ok()
}

/// Hysteresis: returns the new tablet-mode state for the given angle.
/// `current` is None until the first reading.
fn next_state(current: Option<bool>, angle: i64, enter: i64, exit: i64) -> bool {
    match current {
        None => angle >= enter,
        Some(false) if angle >= enter => true,
        Some(true) if angle <= exit => false,
        Some(state) => state,
    }
}

// ---- uinput -----------------------------------------------------------------

const UI_SET_EVBIT: c_ulong = 0x4004_5564;
const UI_SET_SWBIT: c_ulong = 0x4004_556d;
const UI_DEV_SETUP: c_ulong = 0x405c_5503;
const UI_DEV_CREATE: c_ulong = 0x5501;
const UI_DEV_DESTROY: c_ulong = 0x5502;

const EV_SYN: u16 = 0x00;
const EV_SW: u16 = 0x05;
const SYN_REPORT: u16 = 0;
const SW_TABLET_MODE: u16 = 0x01;
const BUS_USB: u16 = 0x03;

#[repr(C)]
struct InputId {
    bustype: u16,
    vendor: u16,
    product: u16,
    version: u16,
}

#[repr(C)]
struct UinputSetup {
    id: InputId,
    name: [u8; 80],
    ff_effects_max: u32,
}

// struct input_event on x86_64 (the only platform this module supports).
#[repr(C)]
struct InputEvent {
    tv_sec: i64,
    tv_usec: i64,
    kind: u16,
    code: u16,
    value: i32,
}

const _: () = assert!(size_of::<UinputSetup>() == 92);
const _: () = assert!(size_of::<InputEvent>() == 24);

extern "C" {
    fn ioctl(fd: c_int, request: c_ulong, ...) -> c_int;
}

fn check(ret: c_int, what: &str) -> Result<(), String> {
    if ret < 0 {
        Err(format!("{what}: {}", io::Error::last_os_error()))
    } else {
        Ok(())
    }
}

struct TabletSwitch {
    file: File,
}

impl TabletSwitch {
    fn create(name: &str) -> Result<Self, String> {
        let file = OpenOptions::new()
            .write(true)
            .open("/dev/uinput")
            .map_err(|e| format!("open /dev/uinput: {e} (is the uinput module loaded?)"))?;
        let fd = file.as_raw_fd();

        let mut setup = UinputSetup {
            id: InputId { bustype: BUS_USB, vendor: 1, product: 1, version: 1 },
            name: [0; 80],
            ff_effects_max: 0,
        };
        let bytes = name.as_bytes();
        let len = bytes.len().min(setup.name.len() - 1);
        setup.name[..len].copy_from_slice(&bytes[..len]);

        // SAFETY: fd is a valid uinput descriptor; the arguments match the
        // request types (int for the *BIT requests, struct pointer for SETUP).
        unsafe {
            check(ioctl(fd, UI_SET_EVBIT, EV_SW as c_int), "UI_SET_EVBIT")?;
            check(ioctl(fd, UI_SET_SWBIT, SW_TABLET_MODE as c_int), "UI_SET_SWBIT")?;
            check(ioctl(fd, UI_DEV_SETUP, &setup as *const UinputSetup), "UI_DEV_SETUP")?;
            check(ioctl(fd, UI_DEV_CREATE), "UI_DEV_CREATE")?;
        }
        Ok(Self { file })
    }

    fn set(&mut self, on: bool) -> Result<(), String> {
        let events = [
            InputEvent { tv_sec: 0, tv_usec: 0, kind: EV_SW, code: SW_TABLET_MODE, value: on as i32 },
            InputEvent { tv_sec: 0, tv_usec: 0, kind: EV_SYN, code: SYN_REPORT, value: 0 },
        ];
        // SAFETY: InputEvent is repr(C) plain data without padding (8+8+2+2+4).
        let bytes = unsafe {
            std::slice::from_raw_parts(events.as_ptr() as *const u8, size_of::<[InputEvent; 2]>())
        };
        self.file
            .write_all(bytes)
            .map_err(|e| format!("write uinput event: {e}"))
    }
}

impl Drop for TabletSwitch {
    fn drop(&mut self) {
        // SAFETY: valid uinput fd; DESTROY takes no argument.
        unsafe { ioctl(self.file.as_raw_fd(), UI_DEV_DESTROY) };
    }
}

// ---- main -------------------------------------------------------------------

fn run(cfg: Config) -> Result<(), String> {
    let mut warned = false;
    let angle_path = loop {
        match find_hinge(&cfg.iio_dir) {
            Some(p) => break p,
            None => {
                if !warned {
                    eprintln!("waiting for the IIO hinge sensor in {}", cfg.iio_dir.display());
                    warned = true;
                }
                sleep(FIND_RETRY);
            }
        }
    };
    eprintln!(
        "using {} (enter >= {}, exit <= {}, poll {} ms)",
        angle_path.display(),
        cfg.enter,
        cfg.exit,
        cfg.poll.as_millis()
    );

    let mut switch = TabletSwitch::create("Hinge Tablet Mode Switch")?;
    let mut tablet: Option<bool> = None;

    loop {
        if let Some(angle) = read_angle(&angle_path) {
            let new = next_state(tablet, angle, cfg.enter, cfg.exit);
            if tablet != Some(new) {
                tablet = Some(new);
                switch.set(new)?;
                eprintln!("tablet mode {} (hinge angle {angle})", if new { "on" } else { "off" });
            }
        }
        sleep(cfg.poll);
    }
}

fn main() -> ExitCode {
    match parse_args(env::args().skip(1)) {
        Ok(Parsed::Help) => {
            println!("{USAGE}");
            ExitCode::SUCCESS
        }
        Ok(Parsed::Run(cfg)) => match run(cfg) {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => {
                eprintln!("error: {e}");
                ExitCode::FAILURE
            }
        },
        Err(e) => {
            eprintln!("error: {e}\n\n{USAGE}");
            ExitCode::from(2)
        }
    }
}

// ---- tests ------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn args(s: &str) -> impl Iterator<Item = String> {
        s.split_whitespace().map(String::from).collect::<Vec<_>>().into_iter()
    }

    #[test]
    fn hysteresis_matches_python_version() {
        // First reading decides by ENTER only.
        assert!(!next_state(None, 299, 300, 270));
        assert!(next_state(None, 300, 300, 270));
        // Laptop -> tablet only at >= enter.
        assert!(!next_state(Some(false), 299, 300, 270));
        assert!(next_state(Some(false), 300, 300, 270));
        // Tablet stays on inside the gap, leaves at <= exit.
        assert!(next_state(Some(true), 271, 300, 270));
        assert!(!next_state(Some(true), 270, 300, 270));
    }

    #[test]
    fn parses_flags_both_forms() {
        match parse_args(args("--enter 310 --exit=260 --poll-ms 500")).unwrap() {
            Parsed::Run(c) => {
                assert_eq!((c.enter, c.exit), (310, 260));
                assert_eq!(c.poll, Duration::from_millis(500));
            }
            Parsed::Help => panic!(),
        }
    }

    #[test]
    fn rejects_bad_input() {
        assert!(parse_args(args("--enter 250")).is_err()); // exit (270) >= enter
        assert!(parse_args(args("--poll-ms 0")).is_err());
        assert!(parse_args(args("--enter")).is_err());
        assert!(parse_args(args("--enter abc")).is_err());
        assert!(parse_args(args("--bogus 1")).is_err());
    }

    #[test]
    fn finds_hinge_in_fake_sysfs() {
        let root = env::temp_dir().join(format!("hinge-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        for (n, name) in [(0, "accel_3d"), (1, "hinge"), (10, "other")] {
            let d = root.join(format!("iio:device{n}"));
            fs::create_dir_all(&d).unwrap();
            fs::write(d.join("name"), format!("{name}\n")).unwrap();
        }
        let hinge = root.join("iio:device1");
        fs::write(hinge.join("in_angl0_label"), "base\n").unwrap();
        fs::write(hinge.join("in_angl1_label"), "hinge\n").unwrap();
        assert_eq!(find_hinge(&root), Some(hinge.join("in_angl1_raw")));
        fs::write(hinge.join("in_angl1_raw"), "336\n").unwrap();
        assert_eq!(read_angle(&hinge.join("in_angl1_raw")), Some(336));
        fs::remove_dir_all(&root).unwrap();
    }
}
