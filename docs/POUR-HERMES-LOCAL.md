# POUR TON HERMES LOCAL (Mac) — à appliquer au prochain build Goose

## Contexte
Backend whoop-band poussé et déployé (commit 963e194, GH Actions en cours).
Nouveautés API que l'app Goose doit exploiter :
1. `/ingest/metrics/daily` renvoie maintenant `metric_authority` : une map
   `{métrique: "measured"|"estimate"|"research"|"gap"}`. L'app doit lire ce champ
   et labeller l'UI (badge "est." pour estimate, "recherche" pour research —
   notamment **spo2_odi qui est research : ne jamais l'afficher comme une mesure**).
2. `spo2_odi` a changé de forme : avant `float`, maintenant
   `{"events_per_hour": float, "authority": "research", "tier": "relative", "note": "..."}`
   → **adapter le parsing Swift** (SimpleAppView / HealthDataStore).

## Patch Swift à appliquer (build Xcode sur ton Mac)

**Fichier : `GooseSwift/GooseBLEClient+Parsing.swift`** (WhoopCloudForwarder.forward)
Inclure la température cutanée dans le feed live (table `skin_temp_sample` vide depuis
toujours — l'app a le candidat mais ne le poste pas) :

```swift
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
      body["skin_temp_raw"] = t   // raw thermistor ADC — relative tier only
    }
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    URLSession.shared.dataTask(with: req).resume()
  }
}
```
Point d'appel (GooseAppModel+PacketPublishing) : passer
`skinTempRaw: latestSkinTemperatureCandidate?.rawValue` (adapter au vrai type du candidat).

**Fichier : parsing de `spo2_odi`** — remplacer partout où c'est lu comme un nombre :
```swift
if let odi = entry["spo2_odi"] as? [String: Any] {
    let eph = odi["events_per_hour"] as? Double
    let authority = odi["authority"] as? String ?? "research"
    // afficher eph avec badge "recherche" — jamais comme une mesure
}
```

## À ne pas oublier
- Après le build : relancer l'app une nuit entière pour peupler skin_temp_sample
  et vérifier les RR (bug intermittent connu — carte t_a8e20a99 board goose).
- Backfill cassé depuis le 16/06 : piste n°1 = notre GET_DATA_RANGE ne coupe pas le
  realtime avant de tirer (le firmware n'envoie l'historique QUE realtime coupé).
  Voir goose/docs/BILAN-ATRIA-COMPLET.md + AUDIT-DATA-QUALITY-2026-09-07.md.
