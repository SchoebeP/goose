# Audit qualité des données — 07/09/2026

Requêtes réelles sur la base (whoop-db). Rejouable : `python3 /opt/data/whoop_audit.py "<sql>"`.

## ✅ Ce qui marche bien
- **HR live** : gap moyen **8 secondes** quand l'app est connectée — excellent.
- **1,46 M échantillons HR** depuis le 3 juin, pipeline stable.
- **RR : 720k échantillons** au total (traités Lipponen-Tarvainen + RMSSD gap-aware).
- **Steps minute** : comptés proprement (590 min, 6 647 pas aujourd'hui pendant les heures connectées).

## 🔴 Problème 1 — Backfill MORT depuis le 16 juin
- `history_sample` : dernière ligne = **2026-06-16**. Plus rien depuis ~3 mois.
- Le trou de **69,7 h** (4 sept soir → 7 sept matin) n'a **pas** été rebouché.
- L'app contient le code (`GET_DATA_RANGE` one-shot on bond, `GooseBLEClient+Commands.swift:1148`)
  mais plus rien n'atterrit en base.
- **Conséquence** : chaque période hors connexion (nuits notamment) = HR du buffer band jamais drainé.
  Le buffer onboard ~jours → si pas drainé toutes les 24-48 h, ça déborde = perte définitive.

## 🟠 Problème 2 — Couverture journalière faible
- Aujourd'hui : **41 %** des minutes couvertes (app connectée ~10 h/24 h).
- 5-6 sept : **0 %** (app pas lancée).
- `skin_temp_sample` : **0 ligne au total** — jamais ingérée (alors que la déviation temp s'affiche
  via un autre chemin ? à vérifier : d'où vient `skin_temp.deviation_c` si la table est vide).

## 🟠 Problème 3 — RR intermittent
- Aujourd'hui : **0** RR stockés alors que HR il y a (37k lignes) → le flux type-40 realtime RR
  n'a pas tourné/pas été persisté aujourd'hui. 720k historiques existent → intermittent.

## Plan d'action (par priorité)
1. **Debugger le backfill** : pourquoi les HISTORICAL_DATA ne sont plus insérés depuis le 16 juin ?
   - regarder `app_log` de l'app iOS autour d'une reconnexion (GET_DATA_RANGE envoyé ? réponse ?)
   - vérifier `history_backfill_state.last_frame_id` (curseur figé ?)
   - hypothèse : changement de code/deploiement mi-juin → régression silencieuse
2. **Drain systématique on-bond** : à chaque reconnexion, tirer l'historique jusqu'à `last_frame_id`,
   afficher dans l'app "backfill : OK / trou de Xh" (honnêteté à la Atria)
3. **skin_temp** : soit ingérer (le champ existe dans les trames), soit couper la métrique
4. **RR intermittent** : corréler avec les app_log (le enable sequence R10/R11 est-il bien renvoyé
   après restauration background ?)
5. *(backlog Atria déjà noté : SpO₂ absolu, badge couverture pas, reason codes, rr_confidence_pct)*

## Mesures de couverture (à refaire après fix)
```sql
SELECT wall_ts::date, round(100.0*count(distinct date_trunc('minute', wall_ts))/1440,0)
FROM hr_sample WHERE wall_ts > now()-interval '8 days' GROUP BY 1 ORDER BY 1;
-- 2026-09-04 → 2 % ; 2026-09-07 → 41 %
```
