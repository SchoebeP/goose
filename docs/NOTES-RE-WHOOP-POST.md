# Notes reverse-engineering-whoop-post (bWanShiTong) — ce qu'on apprend pour Goose

Source : README (23 Ko) du repo (244★, 2 commits — un POST de blog, pas du code).
⚠️ Licence : le repo n'affiche AUCUNE licence → on s'inspire des FAITS protocolaires
(non protégeables), on ne COPIE aucun code. Conforme à notre règle CLAUDE.md.

## 1. La table GATT officielle (confirmée par décompilation de l'APK)

| Char | Nom (APK décompilé) | Sens | Handle |
|---|---|---|---|
| 0x61080002 | **CMD_TO_STRAP** | écriture seule | 0x0010 |
| 0x61080003 | CMD_FROM_STRAP | notify | 0x0012 |
| 0x61080004 | EVENTS_FROM_STRAP | notify | 0x0015 |
| 0x61080005 | DATA_FROM_STRAP | notify | 0x0018 |
| 0x61080007 | MEMFAULT | notify | 0x001b |

→ Nous : cohérent avec notre forward (61080003/04/05) ✓. Le nom MEMFAULT (0x61080007)
est intéressant : c'est du crash-reporting firmware → si on veut diagnostiquer les
disconnects GEN4, écouter 0007 pourrait donner les raisons côté strap. **À ajouter au
scan de caractéristiques (lecture seule, zéro risque).**

## 2. Le format de commande canonique (confirmé)

`aa 0800 a8 23 <seq> <cat> <val> <crc32 LE>` — 13 octets :
- header `aa0800a823` : len=8, crc8=a8, type=0x23 (35!) — notez : **leur "type" 35 = notre type-35** ✓
- `<seq>` : compteur — **NON VÉRIFIÉ par le firmware** (prouvé : le device accepte
  un seq figé/rejoué) → pas besoin de gérer un compteur strict côté app
- catégories : `0x03` start/stop activité (val 01/00, aussi 0x8f=sleep start!),
  `0x0e` broadcast HR on/off, `0x45` alarm off, `0x16` retrieve data
- crc32 LE sur le payload (leur conclusion via crcbeagle)

## 3. LA pépite : les types d'alarme SMART (pas juste heure exacte)

```
0x4201 + timestamp unix LE (next ring) = alarm
  - 7:00/7:01/12:00/4:20 = "Exact time"
  - "Peak 06:20" / "Perform 06:20" / "In the Green 06:20" = alarmes ADAPTATIVES
```
→ **Le strap gère LUI-MÊME les alarmes intelligents** : le téléphone calcule
l'heure optimale (peak/perform/in-the-green = dans la fenêtre de sommeil) et pousse
juste un timestamp "next ring". Le strap vibre tout seul à cette heure, même si le
téléphone meurt pendant la nuit. **C'est LA feature à ajouter à Goose** :
- notre backend sait déjà calculer les cycles de sommeil (sleep_stager + fenêtres)
- l'app pousse `aa100057 23 <seq> 4201 <unix_LE> 00000000 <crc32>` avant la nuit
- commande "alarm off" : cat `0x45` val 00
→ réveil intelligent SANS cloud Whoop, calculé par nous. Carte à créer.

## 4. Health Monitor & data records type-40 (recoupé)

Leurs trames activité (`aa1800ff 2802 <unix> <S/HR/RR…>`) = même famille que notre
type-40 (realtime HR+RR) : unix + HR + RR data + crc. Recoupe nos offsets ✓.
`0x03 0x8f` = "Sleep start" → **le strap a un mode sommeil explicite** (pas juste
de la détection passive) : à tester (start sleep cat 03 val 8f? ou 8f est la cat?)
pour améliorer notre staging.

## 5. Random text commands (recherche/provisioning)

`aa4800f323 <seq> 78 01 "general_ab_test/sigproc_10_sec_dp/sigproc_pdaf/enable_r19_packets" ...`
→ noms de télémétrie firmware qui confirment les pipelines internes (sigproc, PDAF,
r19 packets). Intéressant : **"enable_r19_packets"** = le flux R19 (nos R10/R11 ?)
peut s'activer par nom → piste pour le RR intermittent : un enable par NOM plus
fiable que notre SET_RESEARCH_PACKET(131)×3 ?

## Actions Goose (ajoutées au board)
1. [P1] Écouter 0x61080007 (MEMFAULT) → diagnostiquer les disconnects GEN4
2. [P1] Alarme intelligente locale : backend calcule heure optimale → app pousse 0x4201 —
   feature visible, différenciante, honnête (notre calcul, pas celui de Whoop)
3. [P2] Tester cat 0x03 val 0x8f (sleep start) pour le staging
4. [P2] Comparer "enable_r19_packets" vs notre séquence 131×3 pour le RR intermittent
5. [info] seq non vérifié par le firmware → simplifier notre gestion de seq
