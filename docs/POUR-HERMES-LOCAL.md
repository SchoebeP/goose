# POUR TON HERMES LOCAL (Mac) — patch révusé ensemble, build Goose

*(Version 2 — après review conjointe du code Swift avec l'Hermes VPS. Remplace la v1.)*

## ⚠️ Correction importante vs la v1
La v1 proposait d'appeler `forward(..., skinTempRaw:)` depuis le parsing HR — **faux** :
les events température passent par un autre chemin (`WhoopEventSamples`), et la valeur
à poster est le **RAW** (`candidate.rawValue`), pas les Celsius. Le bon point d'appel =
`GooseAppModel+PacketPublishing.swift:457`.

## Le vrai câblage (3 morceaux)

**1. `GooseBLEClient+Parsing.swift` — WhoopCloudForwarder : nouvelle méthode dédiée**
(juste après `forward(bpm:rrMs:at:)`, ligne ~1024) :

```swift
/// Forward a skin-temperature candidate from TEMPERATURE_LEVEL events.
/// Raw int only — never Celsius (backend stores raw ADC; relative tier policy).
func forwardSkinTemp(rawValue: Int, at date: Date) {
  guard isEnabled else { return }
  queue.async {
    var req = URLRequest(url: self.endpoint)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(self.token, forHTTPHeaderField: "X-Ingest-Token")
    // skin_temp_raw attends un Double côté backend (float), skin_contact optionnel
    let body: [String: Any] = [
      "bpm": 0,   // hmm — voir note (1) ci-dessous
      ...
    ]
  }
}
```

**(1) PROBLÈME détecté en review : l'endpoint POST /ingest/samples ignore `bpm: 0`**
(`if s.bpm:` → pas de ligne HR, OK) MAIS il exige le champ… vérifier le modèle
`SampleIn` : si `bpm: int | None` → envoyer `"bpm": null` + `"skin_temp_raw": <raw>`
+ `"skin_contact": true`. Si `bpm` est requis non-null, envoyer le dernier bpm connu
ou splitter en 2 posts (recommandé : un seul post avec bpm null si accepté).

**2. `GooseAppModel+PacketPublishing.swift:457` — le point d'appel réel :**

```swift
publishSkinTemperatureCandidateStatus(sample.temperatureCandidateSummary)
if let cand = sample.primaryTemperatureCandidate {
  WhoopCloudForwarder.shared.forwardSkinTemp(rawValue: cand.rawValue, at: sample.capturedAt)
}
```
(anti-spam : TEMPERATURE_LEVEL events sont rares — pas besoin de throttle ;
`forwardSkinTemp` throttle à ≥60s en interne si prudent : les events arrivent par rafales.)

**3. Parsing `spo2_odi` (SimpleAppView / HealthDataStore) — le backend a changé le format :**
```swift
// AVANT: entry["spo2_odi"] as? Double
// MAINTENANT:
if let odi = entry["spo2_odi"] as? [String: Any],
   let eph = odi["events_per_hour"] as? Double {
  // authority = odi["authority"] as? String ?? "research" → badge "recherche" dans l'UI
}
```
+ `/ingest/metrics/daily` renvoie `metric_authority: {clé: "measured|estimate|research|gap"}`
→ mapper pour les libellés : measured = rien, estimate = "est.", research = "recherche".

## Checklist build
- [ ] `forwardSkinTemp` avec bpm null (vérifier SampleIn d'abord)
- [ ] Appel depuis PacketPublishing:457 avec `cand.rawValue`
- [ ] Parsing spo2_odi objet + badge authority
- [ ] Build → lancer 1 nuit → vérifier `SELECT count(*) FROM skin_temp_sample;` > 0
- [ ] (séparé, P0) backfill : voir AUDIT-DATA-QUALITY-2026-09-07.md

## État backend (déjà en prod — commit 963e194)
- metric_authority.py + tests pinants (5) — quality gate SonarQube OK
  (new violations 0, new coverage 81.8%)
- spo2_odi = {events_per_hour, authority:"research", tier:"relative", note}
- Patch complet reviewé : goose/docs/POUR-HERMES-LOCAL.md (cette v2 fait foi)
