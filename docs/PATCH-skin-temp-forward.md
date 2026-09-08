// PATCH à appliquer dans GooseSwift/GooseBLEClient+Parsing.swift (WhoopCloudForwarder.forward)
// But: inclure la température cutanée candidate dans le feed live (table skin_temp_sample vide depuis toujours).
// Source du candidat: latestSkinTemperatureCandidateStatus (déjà tracké par l'app).

func forward(bpm: Int, rrMs: [Double], at date: Date, skinTempRaw: Double? = nil) {
  guard isEnabled, bpm > 0 else { return }
  queue.async {
    guard date.timeIntervalSince(self.lastSent) >= 0.9 else { return }
    self.lastSent = date
    var req = URLRequest(url: self.endpoint)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(self.token, forHTTPHeaderField: "X-Ingest-Token")
    var body: [String: Any] = [
      "bpm": bpm,
      "rr_intervals_ms": rrMs,
      "wall_ts": self.iso.string(from: date),
    ]
    if let t = skinTempRaw {
      body["skin_temp_raw"] = t   // honesty: raw thermistor ADC, no degC claim (relative tier only)
    }
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    URLSession.shared.dataTask(with: req).resume()
  }
}

// Point d'appel (GooseAppModel+PacketPublishing): passer le dernier candidat temp:
//   WhoopCloudForwarder.shared.forward(bpm: bpm, rrMs: rr, at: now,
//       skinTempRaw: latestSkinTemperatureCandidate?.rawValue)
// (adapter au vrai type du candidat — voir latestSkinTemperatureCandidateStatus)
