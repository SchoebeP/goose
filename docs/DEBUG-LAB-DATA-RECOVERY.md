# Debug lab Goose — focus DATA RECOVERY (band hors connexion)

Décision pat 08/09 : LE focus = récupérer les données accumulées pendant que la band est
déconnectée du téléphone. On teste des commandes via une app debug, chaque bouton loggue
dans la DB (app_log + raw_frame + command responses).

## Ce qui existe DÉJÀ dans l'app (ne pas réinventer)

1. **Research BT Commands** (More → Debug) : 10 commandes avec boutons + timeout 8s +
   matching réponse/seq + statut ok/failed. Déjà câblé :
   - get_body_location_and_status (84), get_research_packet (132),
     get_extended_battery_info (98), get_battery_pack_info (151),
     get_led_drive (40), get_tia_gain (42), get_bias_offset (44),
     get_device_config_value (121, keyed), get_feature_flag_value (128, keyed),
     toggle_imu_mode_historical (105, payload requis)
2. **Deep links** : `gooseswift://debug-command/<id>?payload=<hex>` → je peux déclencher
   des commandes à distance depuis les messages (Hermes → tel).
3. **Journal GEN4 backfill** (gen4Journal) : narratif français de chaque étape du drain.
4. Séquence Atria déjà en prod dans le backfill : TOGGLE off → 34/22 (×2 formes) →
   fenêtre ~90s → TOGGLE on. + mode "officialOnly" (0x16 seul, après handshake).

## Les NOUVELLES commandes à tester (sources bWanShiTong + Atria + APK)

Priorité = ce qui peut débloquer LE backfill :

| # | Test | Commande | Pourquoi |
|---|------|----------|----------|
| 1 | **Handshake complet avant 0x16** | séquence officielle : HELLO(35)/battery/handshake PUIS REQUEST_HISTORICAL(22) | Zulusierra MITM : la vraie app demande l'historique SEULEMENT après le handshake complet. Notre mode officialOnly envoie peut-être trop tôt |
| 2 | **Catégorie 0x16 "retrieve data"** du post bWanShiTong | aa0800a823 <seq> 16 00 <crc32> | Le post montre 0x16 comme catégorie de COMMANDE (=notre cmd 22). Format V4 vs V5 GEN4 à vérifier |
| 3 | **TOGGLE_IMU_MODE_HISTORICAL (105)** | payload à deviner : tenter 00/01/02 | Si l'IMU passe en mode historique → les STEPS deviennent backfillables (le graal, issue #21 d'Atria) |
| 4 | **enable_r19_packets par NOM** | aa4800f323 <seq> 78 01 "enable_r19_packets"… 32… <crc32> | Le firmware accepte des commandes par nom → peut-être un canal historique alternatif (R19 = summaries ?) |
| 5 | **Sleep start cat 0x8f** | aa0800a823 <seq> 03 8f | Marqueur sommeil explicite ; si le strap loggue les débuts de sommeil dans son buffer → vérité terrain pour nos nuits |
| 6 | **MEMFAULT listen 0x61080007** | subscribe notify | Crash-reports firmware = pourquoi la band droppe silencieusement |

## Ce qu'on loggue dans la DB (déjà majoritairement en place)

- `app_log` : chaque commande envoyée (title=command.id, body=payload hex + résultat)
- `raw_frame` : TOUTES les trames reçues en réponse (le matelas pour re-décoder plus tard)
- `debugCommandResponses` (UI) → aussi poussés dans app_log
- NOUVEAU à ajouter : table ou colonne `debug_command_result` (id, commandNumber, seq,
  resultCode, responseBodyHex, receivedAt) pour requêter proprement l'historique des tests
  côté VPS (sinon on fouille app_log à la main).

## Plan d'action (prochaine session Mac)

1. Ajouter les 6 commandes de test ci-dessus aux debugResearchCommandDefinitions
   (families : "history", "research") + le listener MEMFAULT
2. Ajouter l'endpoint POST /ingest/debug-results côté backend (quiop-band) → table
   debug_command_result ; l'app pousse chaque réponse
3. Protocole de test (une soirée) :
   a. Connecter, lancer le backfill normal → noter combien de type-47 arrivent
   b. Test #1 (handshake puis 0x16) → compter les trames
   c. Test #3 (IMU historical) → vérifier si des type-52/IMU summaries apparaissent
   d. Test #4 (r19 par nom) → regarder les nouvelles trames inconnues dans raw_frame
   e. Comparer les raw_frame reçus par chaque variante → la commande gagnante = celle
      qui fait arriver le plus de type-47/52
4. Chaque test = un bouton → tout est tracé → on analyse côté VPS en SQL
