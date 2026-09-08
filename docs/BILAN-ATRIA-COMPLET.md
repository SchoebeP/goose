# Bilan complet — tous les .md d'Atria (08/09/2026)

Lu : WHOOP4_PROTOCOL_FINDINGS, drain-keeping-flush-design, 16-metric-authority,
DECODER_VALIDATION V24, RESEARCH_BRIEF ACCURACY, WHOOP_REMAINING_PRODUCT_GAPS,
14-spo2-skin-temp-validation, SLEEP_STAGE_DESIGN, 17-muscular-load,
WHOOP_REPLACEMENT_ASSESSMENT, 02-device-ble-map, export-schema, GOAL drain (déjà noté).

## 🧠 Les découvertes qui changent notre roadmap

### 1. SpO₂/temp : PLUS DUR que prévu (doc 14) — corrige ma note précédente
Ils vont PLUS LOIN que "champs DC non pulsatiles" : les offsets 64/66/68 des records V12/V24
sont des u16 little-endian **de signification non établie**. Nommer deux champs "red"/"infrared",
faire leur ratio (→SpO₂) ou diviser le troisième (→°C) = **hypothèses non prouvées**.
→ **NOUS** : on stocke `spo2_red`, `spo2_ir`, `skin_temp_raw` ET on calcule `relative_odi`
sur ce ratio (doc spo2_odi.py). Leur position : même le ratio est une "hypothesis feature,
not a percentage". **Action prioritaire requalifiée : notre ODI doit être étiqueté
"recherche/hypothèse" dans l'API et l'app, jamais comme une mesure.**

### 2. Le drain : leur design final (drain-keeping-flush-design.md)
- **Full-drain-from-oldest = NON-CONVERGENT** (rejoue le plus vieux record flash à ~1x, pas de
  seek) → chemin RETIRÉ. Leur drain = **chunked range-loss slices** uniquement, chaque tranche
  ACK → avance le curseur → progrès permanent, JAMAIS de restart depuis le plus vieux.
- Retry chains à **8 s** mais **uniquement si la tranche précédente a fait du progrès durable**
  (progress-gated → pas de churn).
- **BGProcessingTask overnight window** = leur plus gros reste à faire aussi (le drain de nuit
  planifié). Nous : même gap.
- Transports races fixées : token de fin de page arrivant AVANT le callback ACK précédent →
  déférer d'exactement un token ; rejeu byte-identique d'une page déjà ACKée après reconnexion →
  ignorer. **Deux bugs de course que notre backfill doit aussi gérer.**

### 3. Validation V24 : la structure des records (DECODER_VALIDATION, 37 086 records)
- Records biometriques complets : `payload[0]=0x2f, payload[1]=0x18` (V24), **96 octets**.
- Byte stream `0x19` présent (397 records) — non identifié.
- Pas de records V12 (0x0C) sur leur strap/firmware.
→ Comparer avec nos history_decode.py : si on voit 0x2f/0x18, leur layout validé sur 37k
records peut confirmer nos offsets HR@21.

### 4. Politique d'autorité des métriques (doc 16) — LE pattern à adopter
"Binding engineering policy" ancrée DANS LE CODE (bloc `MetricAuthority` + **tests qui pinent
la politique**). La règle d'honnêteté : pas de donnée fabriquée, estimations étiquetées,
evidence manquante = gap/label/rien — jamais de valeur inventée silencieusement.
→ **Action Goose : un enum MetricAuthority (measured | estimate | research | gap) + tests.**

### 5. Sleep staging : leurs invariants (SLEEP_STAGE_DESIGN)
- **Jamais d'interpolation** : epoch sans HR local = non scorée ; RR jamais emprunté entre epochs.
- Tolérance de gap unifiée **90 s** partout.
- `motionBacked || allowHROnlyEstimate` gate — défaut opt-in OFF.
- Duration-credit fence : les estimations HR-only ne comptent pas dans le crédit de durée.
- Quorum d'intégrité : `max(8, epochCount/3)`.
→ Notre sleep_stager.py : vérifier gap tolerance unifiée + fence durée. Adopter le quorum.

### 6. Charge musculaire (doc 17) — modèle propre, rien copié
Fusion déterministe cardio + musculaire : monotone en poids/reps/RPE, cardio-only =
bit-identique, session non loggée = zéro (jamais inféré de HR), bornée (≤45/séance).
→ Si Goose ajoute un jour la muscu : ces garanties testées sont le cahier des charges.

### 7. Placement produit (REPLACEMENT_ASSESSMENT) — le ton juste
"WHOOP lui-même est provisoire — ils ne l'étiquettent juste pas." Les brevets publics donnent
la STRUCTURE (window selection, intensité), jamais les poids de production. Bonne ligne IP :
s'inspirer de la structure publiée, jamais re-fitter les chiffres WHOOP.
→ Notre "strain à nous" est légitime ; l'étiqueter "notre calcul" (déjà fait dans CLAUDE.md ✓).

### 8. Divers pêchés en passant
- **Batterie 0x2A19** : read initial = valeur POURRIE (stale 100%), notify = vraie. Nous on
  utilise GET_BATTERY(26) type-36 — OK, ne pas changer. Leur doc confirme que le standard ment.
- **UUID CoreBluetooth per-host** : ne jamais hardcoder l'UUID du périphérique (Mac ≠ iPhone).
  Nous : vérifier qu'on persiste par host.
- **Off-wrist** : 2A37 reporte 0, streams proprios inactifs → filtrer les HR=0 prolongés
  comme "non porté" (stats honnêtes).
- **Export recherche anonymisé** (export-schema) : bundle allowlist+denylist avec test statique,
  pseudonyme, bandes d'âge/poids. Si pat veut partager ses données de recherche un jour :
  ce schema est une base.

## 🔧 Fixes à préparer côté nous (ordre de priorité)

1. **[P0] Qualifier l'ODI SpO₂ en "research"** : champ `authority: "research"` dans l'API +
   badge dans l'app Goose. Ne plus jamais l'afficher comme une mesure.
2. **[P0] Backfill : chunked-slice + persist-before-ack** (déjà noté) + les 2 transport races
   (page-end avant ACK callback ; replay byte-identique post-reconnexion) + retry 8s progress-gated.
3. **[P1] MetricAuthority enum + tests pinants** la politique d'honnêteté.
4. [P1] sleep_stager : vérifier 90s unifié + duration-credit fence + quorum max(8, n/3).
5. [P2] HR=0 prolongés → état "non porté" (couverture honnête).
6. [P2] Confirmer records V24 0x2f/0x18 vs notre history_decode (offsets croisés).

## Ce qu'on ne prend PAS
- Leur UI declutter plan, faceoff pages : spécifique à leur app.
- Muscular load : pas de muscu dans Goose v1.
- Research bundle : plus tard si pat veut.
