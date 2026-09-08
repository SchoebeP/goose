# Notes Atria (github.com/adidshaft/atria) — comparaison avec notre stack Goose/whoop-band

Analyse du repo (MIT/Apache-2.0, 149★), 07/09/2026. Atria = app iOS local-first pour strap WHOOP
sans cloud/compte — même terrain que Goose. **Verdict : sur le cœur technique, NOTRE stack est
déjà devant sur plusieurs points.** Ce qui reste à prendre : 4 idées.

## ✅ Ce qu'ils ont et qu'on a DÉJÀ (pas la peine de reprendre)

| Sujet | Atria | Nous (vérifié dans le code) |
|---|---|---|
| Framing BLE | `0xAA \| len u16 LE \| CRC8(poly 07) \| payload \| CRC32`, round-trip vérifié sur 11 trames | **Identique + field-verified** : framing GEN4 documenté dans CLAUDE.md (type/seq/cmd en plus), reassembly par longueur dans `whoop_decode.py` |
| Filtrage RR | Heuristique simple : 300–2000 ms, >20% delta jeté, confiance kept/raw | **Supérieur** : `rr_clean.py` = Lipponen-Tarvainen 2019 (classification ectopic/missed/extra/long-short, QD glissant) + correction spline Catmull-Rom (Peltola 2012) |
| RMSSD gap-aware | Pas mentionné | **On l'a** : split aux gaps avant diffs (bug d'inflation RMSSD corrigé) |
| Strain locale | TRIMP sur HR-réserve personnalisé | Edwards 5-zone TRIMP + scaling ln — même famille "honnête" |
| Temp cutanée relative | Uniquement déviation relative | Pareil (`deviation_c`) ✓ |
| Local-first, no cloud | Oui | Oui (constraint CLAUDE.md) ✓ |

## ⭐ À PRENDRE chez eux (les vraies perles)

### 1. La preuve que SpO₂ Whoop 4 est FABRIQUÉE (issue #31) — ACTION
Leurs champs SpO₂ candidats = niveaux DC 1 Hz **sans composante pulsatile** : un ratio-of-ratios
tombe sur une constante ~80% (artefact). Ils refusent d'afficher.
**Nous** : on stocke `spo2_red/spo2_ir` et on a `_window_spo2_series` + `relative_odi`.
→ Vérifier que notre ODI reste bien RELATIF (désaturation vs baseline perso, pas un % SpO₂ absolu).
Si un écran affiche un % SpO₂ absolu dérivé de ces champs : le retirer, carte vide + raison
("champs DC non pulsatiles — non mesurable sur ce matériel").

### 2. Honnêteté sur les pas journaliers (issue #21) — ACTION
Précision marche comptée prouvée (110 réf → 112 strap, 1.82%). MAIS le drain historique complet
ne peut pas finir contre une connexion HR live → ils **refusent le total du jour** plutôt que
d'afficher un faux chiffre bas. Pas de fallback podomètre téléphone.
**Nous** : steps = band-pass 0.6–3 Hz + peak-count sur l'accel 100 Hz (live), et CLAUDE.md dit
déjà "HR backfillable; steps are NOT" (l'accel brute n'est pas bufferisée).
→ Afficher un badge d'honnêteté sur le total pas : "pas comptés depuis la dernière connexion"
+ couverture (ex: "couvert 9h/24h") plutôt qu'un total qui semble complet.

### 3. Reason codes de métriques — ACTION
Leurs états manquants : `window | gap | beats | confidence | ready`. Une métrique absente est
affichée avec POURQUOI elle manque.
→ À porter sur les endpoints `/ingest/metrics/daily` : chaque champ peut revenir avec
`status: ok|window|gap|beats|low-confidence` pour que l'app Goose affiche la raison au lieu de 0.

### 4. Confiance RR en % (kept/raw)
Ils publient la confiance = kept/raw. Notre `rr_clean` classifie déjà mais n'expose pas le ratio.
→ Ajouter `rr_confidence_pct` dans les réponses métriques (1 ligne de code côté backend).

## 🏗️ Process à voler (non urgent mais malin)

- **`gate_*.sh`** : gates de validation capteur-vs-référence (capture B, audit workout E) —
  l'équivalent hardware de nos verify_all.js. Si un jour on calibre les steps vs un comptage manuel,
  encoder le protocole en script rejouable.
- **`evidence/` gitigné** : arbre de preuves device, jamais commité (données santé perso).
- **`monitor_long_wear.py --preset overnight`** : collecte longue avec checkpointing — nous avons
  l'équivalent iOS (background BLE + restauration), garder l'idée de presets.
- **README "What works / What does not work yet"** : leur section la plus précieuse. Notre GOAL.md
  fait le job côté projet ; une section publique du même ton serait bien si Goose devient public.
- **`docs/SETUP.md` couvrant "les erreurs que vous allez réellement rencontrer"**.

## Licences
MIT + Apache-2.0 : réutilisation de code permise AVEC attribution. Si on porte du code (ex: leur
codec de test), l'ajouter à THIRD_PARTY_LICENSES.md. On ne compte rien porter pour l'instant —
notre implémentation couvre déjà le sujet.

## Backlog résumé (kanban goose)
1. [ ] Vérifier/retirer tout % SpO₂ absolu dérivé des champs red/ir (ODI relatif OK)
2. [ ] Badge couverture sur le total pas ("compté depuis connexion, couvert Xh/24h")
3. [ ] Reason codes (status) sur /ingest/metrics/daily
4. [ ] rr_confidence_pct exposé


---

## Addendum 08/09 — Comment Atria gère le backfill (lire GOAL_strap_steps_drain.md)

### Le mur matériel (device-proven chez eux aussi)
- **L'historique ne stream QUE en drain complet stop-realtime** `[0x16, 0x00]` : le firmware
  n'envoie AUCUNE trame history tant que le flux 2A37 (HR live) est actif (mode chunked
  "realtime-preserving" → `stream5_rx=0`).
- → Cohérent avec notre CLAUDE.md ("HR backfillable; steps are NOT") mais eux précisent :
  c'est le HR **live** qui bloque, pas juste les steps. Le drain exige de COUPER le realtime.

### Le protocole de drain (à copier)
1. **Stop realtime** (`0x16 0x00`) → drain complet `0x22` (GET_DATA_RANGE) + chunks
2. **Persist-before-ack** : ACK `HISTORICAL_DATA_RESULT(23)` SEULEMENT après écriture durable
   des lignes → curseur resumable à travers les déconnexions (jamais de perte ni de doublon)
3. **HISTORY_END** ACK conditionné (retenu si `orphan_not_archived`/`spool_open_failed`)
4. Restaurer le realtime à la fin (`restoreRealtimeAfterHistoryGeneration`)

### Le scheduling (le vrai savoir)
- **Jamais pendant un epoch HR sain** : le live HR est prioritaire à 100%.
- **Drain dans les "gaps naturels"** : reconnexion après déconnexion naturelle
  (`priorConnectionEndedNaturally`), nuit, charge. "Yesterday becomes correct by next morning
  via the overnight natural gap" — hiérarchie assumée : intraday = estimation, nuit = vérité.
- **Interleave pendant le port = impasse révertée** (risque HR, non-convergence prouvée).
- Tout **flag-gated** jusqu'à soak : preuve = `accepted_hr` gap ≈ 0 autour de chaque tranche
  de drain. Dry-run d'abord (`--dryrun` logue la décision sans drainer).

### L'affichage intraday honnête ( REC-1 )
- Total pas du jour = **estimation live par cadence IMU gyro** (zéro coût BLE, chevauche les
  trames déjà sur le lien), libellée **"· estimate" / "Environ N"** — JAMAIS présentée comme
  le vrai compte. Clamp physiologique de cadence. Fallback honnête : dernier jour complet.

### Mapping vers NOS bugs (audit 07/09)
| Notre problème | Leur réponse |
|---|---|
| history_sample figé depuis 16/06 | Vérifier si notre one-shot GET_DATA_RANGE on-bond coupe le realtime avant de tirer (sinon le firmware ne répond jamais) — piste n°1 de notre régression |
| Trous jamais rebouchés (69,7h) | Drain on-reconnect (gap naturel) + curseur persist-before-ack resumable |
| Pas : total trompeur | Leur modèle : estimation live étiquetée + vérité au matin via drain nocturne |
| RR intermittent | Chez eux le drain/type-40 coexistent via le fencing d'epoch — piste : vérifier nos restaurations background |

### Commandes/télémétrie à reprendre
- Télémétrie de drain : `stream5_rx`, `durable_rows`, curseur ACK, `accepted_hr` gap
- Dry-run du prédicat de drain avant de l'activer
- Soak = plusieurs nuits avec preuves avant d'activer par défaut
