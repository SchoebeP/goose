//! Decode raw frame hex lines from stdin to JSON, one object per line.
//!
//! Usage: echo "<frame_hex>" | goose-frame-decode [--device-type GOOSE|GEN4|...]

use goose_core::protocol::{DeviceType, parse_frame_hex};
use std::io::BufRead;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let device_type = args
        .iter()
        .position(|arg| arg == "--device-type")
        .and_then(|index| args.get(index + 1))
        .map(|name| match name.to_ascii_uppercase().as_str() {
            "GEN4" => DeviceType::Gen4,
            "MAVERICK" => DeviceType::Maverick,
            "PUFFIN" => DeviceType::Puffin,
            _ => DeviceType::Goose,
        })
        .unwrap_or(DeviceType::Goose);

    let stdin = std::io::stdin();
    for line in stdin.lock().lines() {
        let Ok(line) = line else { break };
        let frame_hex = line.trim();
        if frame_hex.is_empty() {
            continue;
        }
        match parse_frame_hex(device_type, frame_hex) {
            Ok(parsed) => match serde_json::to_string(&parsed) {
                Ok(json) => println!("{json}"),
                Err(error) => println!("{{\"error\":\"serialize: {error}\"}}"),
            },
            Err(error) => println!("{{\"error\":\"{error}\"}}"),
        }
    }
}
