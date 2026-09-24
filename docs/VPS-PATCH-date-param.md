# VPS patch — `date=` parameter for the per-minute feeds

> **✅ DÉPLOYÉ le 2026-09-11.** Patché en live dans le conteneur `whoop-api`
> (backup: `/root/patches/main.py.bak-20260911` sur le VPS) ET poussé en amont
> dans `SchoebeP/whoop-band` (commit `a63c1ab`) — la prochaine image GHCR
> l'inclura. Vérifié: `date=2026-09-09` → 39 minutes FC / 556 pas;
> mauvaise date → 400; jour courant inchangé.

**Contexte** : la nouvelle UI a une navigation ‹ Aujourd'hui › ‹ Hier › + calendrier.
Pour afficher les courbes FC/pas d'un jour passé, les endpoints per-minute doivent
accepter un paramètre `date`. Aujourd'hui ils ne servent que le jour courant
(le paramètre est ignoré silencieusement).

**À déployer sur le VPS (Hermes)** — patch minuscule, sans risque pour l'existant.

## Endpoints concernés

```
GET /whoop/ingest/hr/minutely?tz=Europe/Paris&date=YYYY-MM-DD
GET /whoop/ingest/steps/minutely?tz=Europe/Paris&date=YYYY-MM-DD
```

## Comportement

- `date` **absent** → comportement actuel (jour local courant, fenêtre minuit
  locale via `tz`). Aucun changement pour les clients existants.
- `date=YYYY-MM-DD` → la fenêtre [00:00, 24:00) de CE jour dans le fuseau `tz`
  au lieu du jour courant. Même forme de réponse (`{minutes:[...], count}`).
- `date` malformé → 400 avec `{"error":"invalid date, expected YYYY-MM-DD"}`.
- Pas de fuite entre utilisateurs : le filtre reste sous le token.

## Implémentation de référence (FastAPI)

```python
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo
from fastapi import HTTPException, Query

@app.get("/ingest/hr/minutely")
def hr_minutely(
    tz: str = Query("UTC"),
    date: str | None = Query(None),   # ← nouveau
    ...
):
    zone = ZoneInfo(tz)

    if date is None:
        day_start = datetime.now(zone).replace(hour=0, minute=0,
                                               second=0, microsecond=0)
    else:
        try:
            day_start = datetime.strptime(date, "%Y-%m-%d").replace(tzinfo=zone)
        except ValueError:
            raise HTTPException(400, "invalid date, expected YYYY-MM-DD")

    day_end = day_start + timedelta(days=1)
    # remplacer la clause « depuis minuit local » par :
    #   WHERE ts >= %(day_start)s AND ts < %(day_end)s
    # (day_start/day_end convertis en UTC avant la requête SQL)
```

Même ajout sur `/ingest/steps/minutely`. Les autres endpoints
(`sleep/nights`, `workouts`, `metrics/daily`) ont déjà leurs propres fenêtres
(`days=`) et n'ont pas besoin de changement.

## Vérification après déploiement

```bash
TOKEN=... # token ingest
curl -s -H "X-Ingest-Token: $TOKEN" \
  "https://latenightgames.fr/whoop/ingest/hr/minutely?tz=Europe/Paris&date=2026-09-10" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print("count:", d["count"])'
# attendu : count > 0 pour un jour avec des données (le paramètre est honoré)
```

L'app envoie déjà `&date=` sur chaque requête — dès que le VPS est à jour, la
navigation ‹ Aujourd'hui › ‹ Hier › affiche les courbes des jours passés sans
mise à jour de l'app.
