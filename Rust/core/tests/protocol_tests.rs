use goose_core::protocol::{
    COMMAND_GET_HELLO, DataPacketBodySummary, DeviceType, EventBodySummary, FrameAccumulator,
    I16SeriesSummary, NormalHistoryBiometrics, PACKET_TYPE_COMMAND_RESPONSE, PACKET_TYPE_EVENT,
    PACKET_TYPE_HISTORICAL_DATA, PACKET_TYPE_REALTIME_DATA, PACKET_TYPE_REALTIME_RAW_DATA,
    ParsedPayload, build_v5_command_frame, build_v5_payload_frame, parse_frame, parse_frame_hex,
};

const GET_HELLO_FRAME: &str = "aa0108000001e67123019101363e5c8d";

#[test]
fn parses_hand_derived_goose_v5_get_hello_frame() {
    let parsed = parse_frame_hex(DeviceType::Goose, GET_HELLO_FRAME).unwrap();

    assert_eq!(parsed.raw_len, 16);
    assert_eq!(parsed.header_len, 8);
    assert_eq!(parsed.declared_len, 8);
    assert_eq!(parsed.payload_hex, "23019101");
    assert_eq!(parsed.packet_type, Some(35));
    assert_eq!(parsed.packet_type_name.as_deref(), Some("COMMAND"));
    assert_eq!(parsed.sequence, Some(1));
    assert_eq!(parsed.command_or_event, Some(145));
    assert!(parsed.header_crc_valid);
    assert!(parsed.payload_crc_valid);
    assert!(parsed.warnings.is_empty());
    assert_eq!(
        parsed.parsed_payload,
        Some(ParsedPayload::Command {
            command: Some(145),
            command_name: Some("GET_HELLO".to_string()),
            data_offset: 3,
            data_hex: "01".to_string(),
            warnings: Vec::new(),
        })
    );
}

#[test]
fn builder_matches_existing_python_command_builder_fixture() {
    let frame = build_v5_command_frame(1, COMMAND_GET_HELLO, &[1]);

    assert_eq!(hex::encode(frame), GET_HELLO_FRAME);
}

#[test]
fn deframer_reassembles_split_v5_frame_and_drops_prefix_noise() {
    let frame = hex::decode(GET_HELLO_FRAME).unwrap();
    let mut accumulator = FrameAccumulator::new(DeviceType::Goose);

    let first = accumulator.feed(&[0x00, 0x01, frame[0], frame[1], frame[2]]);
    assert!(first.frames.is_empty());
    assert_eq!(first.dropped_prefix_len, 2);
    assert_eq!(first.buffered_len, 3);

    let second = accumulator.feed(&frame[3..]);
    assert_eq!(second.frames, vec![frame]);
    assert_eq!(second.buffered_len, 0);
}

#[test]
fn payload_crc_mismatch_preserves_parseable_header_with_warning() {
    let mut frame = hex::decode(GET_HELLO_FRAME).unwrap();
    let last = frame.len() - 1;
    frame[last] ^= 0xff;

    let parsed = parse_frame(DeviceType::Goose, &frame).unwrap();

    assert!(parsed.header_crc_valid);
    assert!(!parsed.payload_crc_valid);
    assert_eq!(parsed.packet_type, Some(35));
    assert!(
        parsed
            .warnings
            .contains(&"payload_crc_mismatch".to_string())
    );
}

#[test]
fn malformed_length_fails_safely() {
    let mut frame = hex::decode(GET_HELLO_FRAME).unwrap();
    frame[2] = 0x04;
    frame[3] = 0x00;

    let error = parse_frame(DeviceType::Goose, &frame).unwrap_err();
    assert!(error.to_string().contains("declared length"));
}

#[test]
fn parses_generic_command_response_payload_contract() {
    let frame = build_v5_payload_frame(&[
        PACKET_TYPE_COMMAND_RESPONSE,
        9,
        COMMAND_GET_HELLO,
        1,
        0,
        0xaa,
        0xbb,
        0xcc,
    ]);
    let parsed = parse_frame(DeviceType::Goose, &frame).unwrap();

    assert_eq!(parsed.packet_type_name.as_deref(), Some("COMMAND_RESPONSE"));
    assert_eq!(
        parsed.parsed_payload,
        Some(ParsedPayload::CommandResponse {
            response_to_command: Some(COMMAND_GET_HELLO),
            response_to_command_name: Some("GET_HELLO".to_string()),
            origin_sequence: Some(1),
            result_code: Some(0),
            data_offset: 5,
            data_hex: "aabbcc".to_string(),
            warnings: Vec::new(),
        })
    );
}

#[test]
fn parses_event_header_and_preserves_unknown_event_body() {
    let frame = build_v5_payload_frame(&[
        PACKET_TYPE_EVENT,
        2,
        17,
        0,
        0x04,
        0x03,
        0x02,
        0x01,
        0x06,
        0x05,
        0,
        0,
        0xde,
        0xad,
        0xbe,
        0xef,
    ]);
    let parsed = parse_frame(DeviceType::Goose, &frame).unwrap();

    assert_eq!(parsed.packet_type_name.as_deref(), Some("EVENT"));
    assert_eq!(
        parsed.parsed_payload,
        Some(ParsedPayload::Event {
            event_id: Some(17),
            event_name: Some("TEMPERATURE_LEVEL".to_string()),
            timestamp_seconds: Some(0x01020304),
            timestamp_subseconds: Some(0x0506),
            data_offset: 12,
            data_hex: "deadbeef".to_string(),
            body_summary: None,
            warnings: Vec::new(),
        })
    );
}

#[test]
fn parses_history_packet_stable_header_and_hr_marker() {
    let frame = build_v5_payload_frame(&[
        PACKET_TYPE_HISTORICAL_DATA,
        18,
        1,
        0x04,
        0x03,
        0x02,
        0x01,
        0x44,
        0x33,
        0x22,
        0x11,
        0x66,
        0x55,
        0xaa,
        0x4d,
        0xbb,
        0xcc,
        0xdd,
        0xee,
        0xff,
    ]);
    let parsed = parse_frame(DeviceType::Goose, &frame).unwrap();

    assert_eq!(parsed.packet_type_name.as_deref(), Some("HISTORICAL_DATA"));
    assert_eq!(
        parsed.parsed_payload,
        Some(ParsedPayload::DataPacket {
            packet_k: Some(18),
            domain: Some("normal_history_with_hr_marker".to_string()),
            status_or_stream: Some(1),
            counter_or_page: Some(0x01020304),
            timestamp_seconds: Some(0x11223344),
            timestamp_subseconds: Some(0x5566),
            hr_marker_offset: Some(14),
            hr_present_marker: Some(0x4d),
            body_offset: 13,
            body_hex: "aa4dbbccddeeff".to_string(),
            body_summary: Some(DataPacketBodySummary::NormalHistory {
                hr_present: Some(true),
                marker_offset: Some(14),
                marker_value: Some(0x4d),
                biometrics: None,
            }),
            warnings: Vec::new(),
        })
    );
}

#[test]
fn normal_history_zero_hr_marker_is_not_treated_as_hr_present() {
    let mut payload = vec![PACKET_TYPE_HISTORICAL_DATA, 9, 1];
    payload.extend_from_slice(&1u32.to_le_bytes());
    payload.extend_from_slice(&2u32.to_le_bytes());
    payload.extend_from_slice(&3u16.to_le_bytes());
    payload.resize(18, 0);
    payload[17] = 0;
    let parsed = parse_frame(DeviceType::Goose, &build_v5_payload_frame(&payload)).unwrap();

    match parsed.parsed_payload.unwrap() {
        ParsedPayload::DataPacket {
            body_summary,
            warnings,
            ..
        } => {
            assert!(warnings.is_empty());
            assert_eq!(
                body_summary,
                Some(DataPacketBodySummary::NormalHistory {
                    hr_present: Some(false),
                    marker_offset: Some(17),
                    marker_value: Some(0),
                    biometrics: Some(NormalHistoryBiometrics {
                        // frame padding keeps byte 18 in-bounds, so this reads the pad zero
                        rr_count: Some(0),
                        rr_intervals_raw: Vec::new(),
                        ppg_green_raw: None,
                        ppg_red_ir_raw: None,
                        gravity_x_milli_g: None,
                        gravity_y_milli_g: None,
                        gravity_z_milli_g: None,
                        skin_contact: None,
                        spo2_red_raw: None,
                        spo2_ir_raw: None,
                        skin_temp_raw: None,
                        ambient_light_raw: None,
                        led_drive_1_raw: None,
                        led_drive_2_raw: None,
                        resp_rate_raw: None,
                        signal_quality_raw: None,
                    }),
                })
            );
        }
        other => panic!("expected data packet, got {other:?}"),
    }
}

#[test]
fn parses_r17_optical_body_offsets_and_signed_sample_stats() {
    let mut payload = vec![0; 32];
    payload[0] = PACKET_TYPE_HISTORICAL_DATA;
    payload[1] = 17;
    payload[2] = 1;
    put_u16(&mut payload, 13, (1 << 9) | (1 << 11));
    payload[15..=20].copy_from_slice(&[1, 2, 3, 4, 5, 6]);
    put_u16(&mut payload, 24, 3);
    put_i16(&mut payload, 26, 1000);
    put_i16(&mut payload, 28, -1000);
    put_i16(&mut payload, 30, 200);

    let parsed = parse_frame(DeviceType::Goose, &build_v5_payload_frame(&payload)).unwrap();

    match parsed.parsed_payload.unwrap() {
        ParsedPayload::DataPacket {
            body_summary,
            warnings,
            ..
        } => {
            assert!(warnings.is_empty());
            assert_eq!(
                body_summary,
                Some(DataPacketBodySummary::R17OpticalOrLabradorFiltered {
                    flags: Some(0x0a00),
                    flag_bit_9: Some(true),
                    flag_bit_11: Some(true),
                    channels_or_gain: vec![1, 2, 3, 4, 5, 6],
                    sample_count: Some(3),
                    samples: Some(I16SeriesSummary {
                        name: "r17_samples".to_string(),
                        offset: 26,
                        expected_count: 3,
                        parsed_count: 3,
                        min: Some(-1000),
                        max: Some(1000),
                        sum: 200,
                        preview: vec![1000, -1000, 200],
                    }),
                    warnings: Vec::new(),
                })
            );
        }
        other => panic!("expected data packet, got {other:?}"),
    }
}

#[test]
fn r17_truncated_samples_warn_without_losing_available_values() {
    let mut payload = vec![0; 28];
    payload[0] = PACKET_TYPE_HISTORICAL_DATA;
    payload[1] = 17;
    put_u16(&mut payload, 24, 4);
    put_i16(&mut payload, 26, -7);

    let parsed = parse_frame(DeviceType::Goose, &build_v5_payload_frame(&payload)).unwrap();

    match parsed.parsed_payload.unwrap() {
        ParsedPayload::DataPacket {
            body_summary,
            warnings,
            ..
        } => {
            assert!(warnings.contains(&"r17_samples_truncated".to_string()));
            let Some(DataPacketBodySummary::R17OpticalOrLabradorFiltered {
                samples,
                warnings: summary_warnings,
                ..
            }) = body_summary
            else {
                panic!("expected r17 body summary");
            };
            assert!(summary_warnings.contains(&"r17_samples_truncated".to_string()));
            assert_eq!(samples.unwrap().parsed_count, 1);
        }
        other => panic!("expected data packet, got {other:?}"),
    }
}

#[test]
fn parses_k10_raw_motion_offsets_without_claiming_units() {
    let mut payload = vec![0; 1288];
    payload[0] = PACKET_TYPE_REALTIME_RAW_DATA;
    payload[1] = 10;
    payload[17] = 72;
    put_i16(&mut payload, 85, 1);
    put_i16(&mut payload, 87, -2);
    put_i16(&mut payload, 89, 3);
    put_i16(&mut payload, 1088, -10);
    put_i16(&mut payload, 1090, 20);

    let parsed = parse_frame(DeviceType::Goose, &build_v5_payload_frame(&payload)).unwrap();

    match parsed.parsed_payload.unwrap() {
        ParsedPayload::DataPacket {
            body_summary,
            warnings,
            ..
        } => {
            assert!(warnings.is_empty());
            let Some(DataPacketBodySummary::RawMotionK10 {
                heart_rate,
                axes,
                warnings: summary_warnings,
            }) = body_summary
            else {
                panic!("expected k10 body summary");
            };
            assert_eq!(heart_rate, Some(72));
            assert!(summary_warnings.is_empty());
            assert_eq!(axes.len(), 6);
            assert_eq!(axes[0].name, "accelerometer_x");
            assert_eq!(axes[0].expected_count, 100);
            assert_eq!(axes[0].parsed_count, 100);
            assert_eq!(axes[0].min, Some(-2));
            assert_eq!(axes[0].max, Some(3));
            assert_eq!(axes[0].sum, 2);
            assert_eq!(axes[5].name, "gyroscope_z");
            assert_eq!(axes[5].min, Some(-10));
            assert_eq!(axes[5].max, Some(20));
        }
        other => panic!("expected data packet, got {other:?}"),
    }
}

#[test]
fn parses_k21_grouped_motion_offsets_and_counts() {
    let mut payload = vec![0; 1038];
    payload[0] = PACKET_TYPE_REALTIME_DATA;
    payload[1] = 21;
    put_u16(&mut payload, 14, 321);
    put_u16(&mut payload, 16, 3);
    put_u16(&mut payload, 622, 3);
    put_i16(&mut payload, 20, -1);
    put_i16(&mut payload, 22, 2);
    put_i16(&mut payload, 24, -3);
    put_i16(&mut payload, 1032, 50);
    put_i16(&mut payload, 1034, 60);
    put_i16(&mut payload, 1036, 70);

    let parsed = parse_frame(DeviceType::Goose, &build_v5_payload_frame(&payload)).unwrap();

    match parsed.parsed_payload.unwrap() {
        ParsedPayload::DataPacket {
            body_summary,
            warnings,
            ..
        } => {
            assert!(warnings.is_empty());
            let Some(DataPacketBodySummary::RawMotionK21 {
                field_x,
                group_1_count,
                group_2_count,
                axes,
                warnings: summary_warnings,
            }) = body_summary
            else {
                panic!("expected k21 body summary");
            };
            assert_eq!(field_x, Some(321));
            assert_eq!(group_1_count, Some(3));
            assert_eq!(group_2_count, Some(3));
            assert!(summary_warnings.is_empty());
            assert_eq!(axes.len(), 6);
            assert_eq!(axes[0].name, "group_1_axis_0");
            assert_eq!(axes[0].preview, vec![-1, 2, -3]);
            assert_eq!(axes[0].sum, -2);
            assert_eq!(axes[5].name, "group_2_axis_2");
            assert_eq!(axes[5].preview, vec![50, 60, 70]);
            assert_eq!(axes[5].sum, 180);
        }
        other => panic!("expected data packet, got {other:?}"),
    }
}

#[test]
fn truncated_long_motion_frame_keeps_partial_samples_with_quality_warnings() {
    let mut payload = vec![0; 1038];
    payload[0] = PACKET_TYPE_REALTIME_DATA;
    payload[1] = 21;
    put_u16(&mut payload, 14, 321);
    put_u16(&mut payload, 16, 100);
    put_i16(&mut payload, 20, -1);
    put_i16(&mut payload, 22, 2);
    put_i16(&mut payload, 24, -3);
    let mut frame = build_v5_payload_frame(&payload);
    frame.truncate(180);

    let parsed = parse_frame(DeviceType::Goose, &frame).unwrap();

    assert_eq!(parsed.raw_len, 180);
    assert!(parsed.declared_len > parsed.raw_len);
    assert!(!parsed.payload_crc_valid);
    assert_eq!(parsed.payload_crc_hex, "");
    assert!(parsed.warnings.contains(&"frame_truncated".to_string()));
    assert!(
        parsed
            .warnings
            .contains(&"payload_crc_unavailable_due_to_truncated_frame".to_string())
    );
    assert!(
        !parsed
            .warnings
            .contains(&"payload_crc_mismatch".to_string())
    );

    match parsed.parsed_payload.unwrap() {
        ParsedPayload::DataPacket {
            body_summary,
            warnings,
            ..
        } => {
            assert!(warnings.contains(&"group_1_axis_0_truncated".to_string()));
            let Some(DataPacketBodySummary::RawMotionK21 {
                axes,
                warnings: summary_warnings,
                ..
            }) = body_summary
            else {
                panic!("expected k21 body summary");
            };
            assert!(summary_warnings.contains(&"group_1_axis_0_truncated".to_string()));
            assert_eq!(axes[0].name, "group_1_axis_0");
            assert_eq!(axes[0].expected_count, 100);
            assert_eq!(axes[0].parsed_count, 76);
            assert_eq!(axes[0].preview[0..3], [-1, 2, -3]);
        }
        other => panic!("expected data packet, got {other:?}"),
    }
}

#[test]
fn truncated_non_data_frame_fails_instead_of_becoming_decoded_evidence() {
    let mut frame = build_v5_command_frame(1, COMMAND_GET_HELLO, &[1, 2, 3, 4, 5, 6, 7, 8]);
    frame.truncate(frame.len() - 3);

    let error = parse_frame(DeviceType::Goose, &frame).unwrap_err();

    assert!(error.to_string().contains("declared length"));
}

#[test]
fn short_data_packets_preserve_raw_body_and_warn() {
    let frame = build_v5_payload_frame(&[PACKET_TYPE_HISTORICAL_DATA, 18, 1, 2]);
    let parsed = parse_frame(DeviceType::Goose, &frame).unwrap();

    assert!(
        parsed
            .warnings
            .contains(&"data_packet_header_too_short".to_string())
    );
    assert!(
        parsed
            .warnings
            .contains(&"history_hr_marker_missing".to_string())
    );
    assert_eq!(
        parsed.parsed_payload,
        Some(ParsedPayload::DataPacket {
            packet_k: Some(18),
            domain: Some("normal_history_with_hr_marker".to_string()),
            status_or_stream: Some(1),
            counter_or_page: None,
            timestamp_seconds: None,
            timestamp_subseconds: None,
            hr_marker_offset: Some(14),
            hr_present_marker: None,
            body_offset: 4,
            body_hex: String::new(),
            body_summary: Some(DataPacketBodySummary::NormalHistory {
                hr_present: None,
                marker_offset: Some(14),
                marker_value: None,
                biometrics: None,
            }),
            warnings: vec![
                "data_packet_header_too_short".to_string(),
                "history_hr_marker_missing".to_string(),
            ],
        })
    );
}

fn put_u16(bytes: &mut [u8], offset: usize, value: u16) {
    bytes[offset..offset + 2].copy_from_slice(&value.to_le_bytes());
}

fn put_i16(bytes: &mut [u8], offset: usize, value: i16) {
    bytes[offset..offset + 2].copy_from_slice(&value.to_le_bytes());
}

fn put_f32(bytes: &mut [u8], offset: usize, value: f32) {
    bytes[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
}

#[test]
fn decodes_v24_normal_history_biometric_fields() {
    // Synthetic k=24 record with known words at the reference-verified offsets
    // (payload-relative; frame-absolute minus 4). 88 bytes = a 96-byte V24 frame body.
    let mut payload = vec![0u8; 88];
    payload[0] = PACKET_TYPE_HISTORICAL_DATA;
    payload[1] = 24;
    payload[2] = 1;
    payload[17] = 72; // heart-rate marker
    payload[18] = 3; // rr_count
    put_u16(&mut payload, 19, 810);
    put_u16(&mut payload, 21, 833);
    put_u16(&mut payload, 23, 825);
    put_u16(&mut payload, 29, 12345); // ppg_green
    put_u16(&mut payload, 31, 2345); // ppg_red_ir
    put_f32(&mut payload, 36, 0.021);
    put_f32(&mut payload, 40, -0.984);
    put_f32(&mut payload, 44, 0.173);
    payload[51] = 1; // skin_contact on-wrist
    put_u16(&mut payload, 64, 587); // spo2_red
    put_u16(&mut payload, 66, 585); // spo2_ir
    put_u16(&mut payload, 68, 930); // skin_temp
    put_u16(&mut payload, 70, 4); // ambient
    put_u16(&mut payload, 72, 31); // led_drive_1
    put_u16(&mut payload, 74, 27); // led_drive_2
    put_u16(&mut payload, 76, 402); // resp_rate_raw
    put_u16(&mut payload, 78, 91); // signal_quality

    let parsed = parse_frame(DeviceType::Goose, &build_v5_payload_frame(&payload)).unwrap();

    let ParsedPayload::DataPacket { body_summary, .. } = parsed.parsed_payload.unwrap() else {
        panic!("expected data packet");
    };
    let Some(DataPacketBodySummary::NormalHistory {
        hr_present,
        marker_value,
        biometrics: Some(biometrics),
        ..
    }) = body_summary
    else {
        panic!("expected normal history with biometrics");
    };

    assert_eq!(hr_present, Some(true));
    assert_eq!(marker_value, Some(72));
    assert_eq!(biometrics.rr_count, Some(3));
    assert_eq!(biometrics.rr_intervals_raw, vec![810, 833, 825]);
    assert_eq!(biometrics.ppg_green_raw, Some(12345));
    assert_eq!(biometrics.ppg_red_ir_raw, Some(2345));
    assert_eq!(biometrics.gravity_x_milli_g, Some(21));
    assert_eq!(biometrics.gravity_y_milli_g, Some(-984));
    assert_eq!(biometrics.gravity_z_milli_g, Some(173));
    assert_eq!(biometrics.skin_contact, Some(1));
    assert_eq!(biometrics.spo2_red_raw, Some(587));
    assert_eq!(biometrics.spo2_ir_raw, Some(585));
    assert_eq!(biometrics.skin_temp_raw, Some(930));
    assert_eq!(biometrics.ambient_light_raw, Some(4));
    assert_eq!(biometrics.led_drive_1_raw, Some(31));
    assert_eq!(biometrics.led_drive_2_raw, Some(27));
    assert_eq!(biometrics.resp_rate_raw, Some(402));
    assert_eq!(biometrics.signal_quality_raw, Some(91));
}

#[test]
fn rr_interval_slots_are_capped_at_five() {
    let mut payload = vec![0u8; 88];
    payload[0] = PACKET_TYPE_HISTORICAL_DATA;
    payload[1] = 12;
    payload[18] = 9; // claims more RR intervals than the record has slots for
    for index in 0..5 {
        put_u16(&mut payload, 19 + index * 2, 800 + index as u16);
    }

    let parsed = parse_frame(DeviceType::Goose, &build_v5_payload_frame(&payload)).unwrap();

    let ParsedPayload::DataPacket { body_summary, .. } = parsed.parsed_payload.unwrap() else {
        panic!("expected data packet");
    };
    let Some(DataPacketBodySummary::NormalHistory {
        biometrics: Some(biometrics),
        ..
    }) = body_summary
    else {
        panic!("expected normal history with biometrics");
    };
    assert_eq!(biometrics.rr_count, Some(9));
    assert_eq!(biometrics.rr_intervals_raw, vec![800, 801, 802, 803, 804]);
}

#[test]
fn k18_and_k7_history_records_do_not_claim_v24_biometrics() {
    for packet_k in [7u8, 18u8] {
        let mut payload = vec![0u8; 88];
        payload[0] = PACKET_TYPE_HISTORICAL_DATA;
        payload[1] = packet_k;

        let parsed = parse_frame(DeviceType::Goose, &build_v5_payload_frame(&payload)).unwrap();

        let ParsedPayload::DataPacket { body_summary, .. } = parsed.parsed_payload.unwrap() else {
            panic!("expected data packet");
        };
        let Some(DataPacketBodySummary::NormalHistory { biometrics, .. }) = body_summary else {
            panic!("expected normal history for k={packet_k}");
        };
        assert_eq!(biometrics, None, "k={packet_k} must not decode V24 fields");
    }
}

#[test]
fn decodes_battery_level_event_fields() {
    // BATTERY_LEVEL(3): soc u16@13 (percent x10), current i16@16, flags u8@22 bit0.
    let mut payload = vec![0u8; 24];
    payload[0] = PACKET_TYPE_EVENT;
    payload[1] = 5;
    put_u16(&mut payload, 2, 3);
    put_u16(&mut payload, 13, 874); // 87.4%
    put_i16(&mut payload, 16, -12); // discharging
    payload[22] = 0x01; // charging bit set

    let parsed = parse_frame(DeviceType::Goose, &build_v5_payload_frame(&payload)).unwrap();

    let ParsedPayload::Event { body_summary, .. } = parsed.parsed_payload.unwrap() else {
        panic!("expected event");
    };
    assert_eq!(
        body_summary,
        Some(EventBodySummary::BatteryLevel {
            state_of_charge_tenths: Some(874),
            battery_current_raw: Some(-12),
            charging_flags: Some(0x01),
            charging: Some(true),
        })
    );
}

#[test]
fn extended_battery_event_decodes_only_the_verified_current_word() {
    let mut payload = vec![0u8; 24];
    payload[0] = PACKET_TYPE_EVENT;
    payload[1] = 5;
    put_u16(&mut payload, 2, 63);
    put_i16(&mut payload, 16, 145); // charging
    payload[22] = 0x01; // must be ignored for event 63

    let parsed = parse_frame(DeviceType::Goose, &build_v5_payload_frame(&payload)).unwrap();

    let ParsedPayload::Event { body_summary, .. } = parsed.parsed_payload.unwrap() else {
        panic!("expected event");
    };
    assert_eq!(
        body_summary,
        Some(EventBodySummary::BatteryLevel {
            state_of_charge_tenths: None,
            battery_current_raw: Some(145),
            charging_flags: None,
            charging: None,
        })
    );
}

#[test]
fn wrist_events_map_to_on_wrist_state() {
    for (event_id, expected_on_wrist) in [(9u16, true), (10u16, false)] {
        let mut payload = vec![0u8; 12];
        payload[0] = PACKET_TYPE_EVENT;
        payload[1] = 5;
        put_u16(&mut payload, 2, event_id);

        let parsed = parse_frame(DeviceType::Goose, &build_v5_payload_frame(&payload)).unwrap();

        let ParsedPayload::Event {
            event_name,
            body_summary,
            ..
        } = parsed.parsed_payload.unwrap()
        else {
            panic!("expected event");
        };
        assert_eq!(
            event_name.as_deref(),
            Some(if expected_on_wrist { "WRIST_ON" } else { "WRIST_OFF" })
        );
        assert_eq!(
            body_summary,
            Some(EventBodySummary::WristState {
                on_wrist: expected_on_wrist
            })
        );
    }
}
