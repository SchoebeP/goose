Salut ! Travail préparé depuis le VPS — applique ces patches au projet Goose (/opt/data/goose ou ton checkout local), puis build Xcode et teste une nuit.

== CONTEXTE BACKEND (déjà déployé, commits 963e194 + 58c3298) ==
1. POST /ingest/samples accepte maintenant un post "température seule" : {"bpm": null, "skin_temp_raw": <Double>, "skin_contact": 1, "wall_ts": "..."} — le modèle SamplesIn a bpm: int|None.
2. GET /ingest/metrics/daily renvoie "metric_authority": {clé: "measured"|"estimate"|"research"|"gap"} → mapper pour les libellés UI (measured=rien, estimate="est.", research="recherche", gap=masquer).
3. "spo2_odi" a CHANGÉ DE FORME : avant float, maintenant {"events_per_hour": float, "authority": "research", "tier": "relative", "note": "..."} → adapter le parsing Swift et afficher avec badge "recherche", jamais comme une mesure.

== PATCH 1 : forward température cutanée (le bug : skin_temp_sample est vide depuis toujours, l'app a le candidat mais ne le poste pas) ==

Fichier GooseSwift/GooseBLEClient+Parsing.swift — ajoute cette méthode dans WhoopCloudForwarder (après forward(bpm:rrMs:at:), ~ligne 1037) :

  /// Forward a skin-temperature candidate from TEMPERATURE_LEVEL events.
  /// Raw int only — never Celsius (backend policy: raw ADC, relative tier).
  func forwardSkinTemp(rawValue: Int, at date: Date) {
    guard isEnabled else { return }
    queue.async {
      let body: [String: Any] = [
        "bpm": NSNull(),
        "skin_temp_raw": Double(rawValue),
        "skin_contact": 1,
        "wall_ts": self.iso.string(from: date),
      ]
      var req = URLRequest(url: self.endpoint)
      req.httpMethod = "POST"
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
      req.setValue(self.token, forHTTPHeaderField: "X-Ingest-Token")
      req.httpBody = try? JSONSerialization.data(withJSONObject: body)
      URLSession.shared.dataTask(with: req).resume()
    }
  }

NOTE anti-spam : TEMPERATURE_LEVEL arrive par rafales ; ajoute un throttle interne ≥60s (comme lastSent pour HR, mais variable séparée lastTempSent).

== PATCH 2 : point d'appel (le vrai endroit — PAS le parsing HR) ==

Fichier GooseSwift/GooseAppModel+PacketPublishing.swift, ~ligne 457, juste après publishSkinTemperatureCandidateStatus(sample.temperatureCandidateSummary) :

  if let cand = sample.primaryTemperatureCandidate {
    WhoopCloudForwarder.shared.forwardSkinTemp(rawValue: cand.rawValue, at: sample.capturedAt)
  }

(TemperatureEventCandidate a bien .rawValue: Int — WhoopEventSamples.swift:156.)

== PATCH 3 : parsing spo2_odi (SimpleAppView / HealthDataStore+CoachSummaries) ==

Remplace partout "entry["spo2_odi"] as? Double" par :

  if let odi = entry["spo2_odi"] as? [String: Any],
     let eph = odi["events_per_hour"] as? Double {
    let authority = odi["authority"] as? String ?? "research"
    // afficher eph avec badge "recherche" — jamais comme une mesure
  }

== CHECKLIST FINALE ==
- [ ] Patch 1+2 appliqués, build OK
- [ ] Patch 3 appliqué, aucun "as? Double" restant sur spo2_odi (grep spo2_odi GooseSwift/)
- [ ] Lancer l'app ≥1 nuit → vérifier côté VPS : python3 /opt/data/whoop_audit.py "SELECT count(*) FROM skin_temp_sample;" doit être > 0
- [ ] RAPPEL P0 : backfill mort depuis le 16/06. Piste n°1 (source Atria, GOAL_strap_steps_drain) : le firmware n'envoie l'historique QUE si le realtime 2A37 est coupé avant GET_DATA_RANGE. Vérifier dans GooseBLEClient+Commands.swift:1148 si on coupe le realtime avant le one-shot backfill. Docs complètes : goose/docs/BILAN-ATRIA-COMPLET.md + AUDIT-DATA-QUALITY-2026-09-07.md.
- [ ] Rétention raw_frame nouvelle (défaut pat) : raw = queue de décodage, supprimé après insertion durable, 1000 dernières gardées pour debug. Type-43 et 47-larges conservés (sources pulse/steps + layout non décodé). Aucun impact app.
