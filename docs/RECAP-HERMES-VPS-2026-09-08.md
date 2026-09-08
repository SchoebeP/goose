# RECAP pour Hermes VPS — session Mac du 7-8 septembre 2026
(from Pat's Mac, branch main, HEAD 4ea65d4 pushed to origin)

## Ce qui s'est passé (chronologique)

1. **Bug token (P0, résolu)** : depuis le 07/09 ~12:54 UTC, plus AUCUNE donnée
   n'arrivait au VPS. Cause : `$(WHOOP_INGEST_TOKEN)` dans Info.plist
   s'expandait en VIDE malgré GooseSecrets.xcconfig en baseConfigurationReference
   → chaque POST partait avec `X-Ingest-Token: ""` → 401 silencieux.
   Fix : injecter le token directement dans Info.plist avant install (le xcconfig
   n'est pas appliqué par le build system de cette cible). Le repo garde un
   Info.plist vide (pas de secret commité). Vérifié : le flux live est reparti
   (9-10k hr_sample / 12h).

2. **Crash app 30 s (résolu)** : iOS tuait l'app (cpu_resource_fatal ×2,
   diskwrites_resource ×1 — 4,3 Go écrits/68 min, footprint 37 Mo→2,9 Go).
   Cause : mes compteurs de backfill (gen4BackfillPacketCount/Bytes,
   @Published) écrits À CHAQUE frame BLE (~70/s) → re-render SwiftUI complet
   par frame. Fix : accumulateurs internes sous lock, publication batchée
   1×/s. Confirmé stable depuis.

3. **Progress bar backfill (livré)** : barre temps (pas de vrai % — le
   bracelet ne annonce jamais son total), ETA, octets + Ko/s. OK.

4. **Patches du TEXTE-HERMES-MAC.md** :
   - Patch 1+2 (forwardSkinTemp + appel PacketPublishing) : APPLIQUÉS,
     commit 176976d, pushé.
   - Patch 3 (spo2_odi) : NON APPLICABLE — le Swift de main n'a jamais parsé
     cette clé (seul un worktree orphelin .claude/worktrees/ref-repo-upgrades
     la référençait). Checklist grep = déjà 0 occurrence.
   - ⚠️ Après UNE nuit : skin_temp_sample = toujours 0 lignes. Cause : la
     bande n'a JAMAIS émis d'event 17 (TEMPERATURE_LEVEL) — 0 frame dans
     raw_frame all-time. Le patch est prêt et tirera au premier event.
     Piste à creuser : sur ce firmware la temp peau passe peut-être par
     un autre event ID (16 ou 33 — payloads collectés dans
     .claude/temp_ev33*.py sur le Mac, pas encore décodés).

5. **Backfill GEN4 — test Atria (CODÉ, PAS ENCORE VÉRIFIÉ SUR LE BANDE)** :
   - Diagnostic : le 23/07 (seul pull qui a marché : 580 frames type-47),
     la séquence tournait AVANT que le realtime soit actif. Depuis, toutes
     nos tentatives envoyaient cmd34/22 PENDANT le stream realtime optique
     → la bande ignore silencieusement (pas d'écho type-36, 0 type-47).
   - Piste Atria appliquée (commit 4ea65d4, pushé) : le backfill coupe
     maintenant le realtime (TOGGLE_REALTIME_HR off) → 1 s → cmd34 → cmd22
     → fenêtre 90 s → TOGGLE_REALTIME_HR(on) à la fin.
   - ⚠️ VERDICT EN ATTENTE : l'iPhone est passé "unavailable" pendant le
     build final — la version Atria N'EST PAS INSTALLÉE sur le téléphone
     (le binaire qui y est tourne encore sans le fix). La prochaine session
     Mac doit : rebuild + install + déclencher un backfill après un vrai
     gap (10 min BT off) et vérifier : écho cmd22 (type-36, payload
     commence par bb02) + type-47 dans raw_frame.

## État du repo
- main = 4ea65d4 (pushé). simple = 5dbee2d (pushé).
- Modifs locales non commitées sur main : GooseSwift/Info.plist (token, à ne
  JAMAIS committer).
- Stashes sur simple : 2 (vieux WIP, safe à drop).
- iPhone "unavailable" en fin de session — probablement débranché/éteint par Pat.

## Checklist pour la prochaine fois (Mac ou VPS-side analysis)
- [ ] Rebuild main + install Atria sur l'iPhone, tester backfill après gap réel
- [ ] Vérifier écho cmd22 + type-47 côté VPS après ce test
- [ ] Décoder les payloads des events 16/33 (candidats température) —
      données brutes dispo dans raw_frame
- [ ] skin_temp_sample > 0 quand le bon event sera identifié/émis
