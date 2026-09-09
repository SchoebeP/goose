# STABILITY AUDIT — nuit du 8 au 9 septembre 2026 (analysis nocturne, Hermes local)

Source: `app_log`, `raw_frame`, `hr_sample` dans Postgres du VPS (container `whoop-api`).
Toutes les heures sont **UTC** (local = UTC+2).

## Verdict en une ligne

La nuit du 07 au 08/09, **~7,8 h de HR perdues** (23:45 → 07:33) : une déconnexion
"connection timed out" à 23:45:25 suivie d'un `connect failed`, puis **plus aucune
activité app pendant 2 h 08** — l'app iOS a été suspendue par le système et n'a plus
réessayé. Ce n'est PAS la bande qui a disparu : c'est l'app qui s'est rendormie sans
replanifier de tentative.

## Les chiffres (fenêtre 09-07 00:00 → 09-08 23:00 UTC)

| Fenêtre morte | Durée | Cause racine |
|---|---|---|
| 09-07 00:00 → 10:00 | ~10 h | (probablement l'app fermée/veille pendant la nuit, avant la session du matin) |
| 09-07 12:50 → 17:24 | 4,5 h | storms de reconnect ("timed out unexpectedly" en boucle) puis silence |
| 09-07 21:00 → 23:01 | ~2 h | coupure courte, récupérée à 23:01 |
| **09-07 23:45 → 09-08 07:33** | **7,8 h** | **voir chronologie ci-dessous** |

Total ~19 h "mortes" sur 47 h ≈ **40 % de perte** sur les deux derniers jours.

## Chronologie de la perte nocturne (23:45:02 → 07:33:00)

1. `23:45:02` — flux OK (optical=49, hr=50 frames/5 min). `connection.state` normal.
2. `23:45:12` — cycle de restauration iOS (state restoration) : `central.restore_state`,
   `reconnect.state=restored`, `connection.state=ready` **sans didConnect réel** —
   exactement le scénario "dead link" documenté dans CLAUDE.md.
3. `23:45:12` — l'app envoie quand même la séquence history (cmd 34 + 22) sur ce lien fantôme.
4. `23:45:12` — **"The connection has timed out unexpectedly."** → disconnect →
   reconnect → `connect.succeeded` (cached!) à 23:45:17 → re-souscription →
   cmd 34/22 renvoyés → **8 s plus tard : encore "timed out unexpectedly"** à 23:45:25.
5. `23:45:25` — `connect failed`. **SILENCE TOTAL** (plus rien dans app_log sauf 13
   `scene_phase` sporadiques jusqu'à 02:07).
6. `01:53:57` — une tentative de plus : **"Failed to encrypt the connection, the
   connection has timed out unexpectedly"** → `connect failed`. Puis rien.
7. `03:22-03:24` — relance app (state restoration) : `reconnect.state=already
   connected` **sur un lien mort** — aucune écriture réelle tentée, aucun flux.
8. `07:33:00` — relance (`central.create`, bluetooth on) : cette fois connect réel,
   discovery, hello, writes acceptées → flux revient instantanément (bande encore là,
   batterie 79 %). **Le bracelet n'a jamais disparu ; c'est l'app qui dormait.**

## Cause racine identifiée (2 niveaux)

**Niveau 1 — lien fantôme post-restauration (connu, mal détecté).** Après state
restoration l'app croit "connected/ready" mais le lien est mort. Les écritures
cmd34/22 ont échoué ("timed out" = le write n'a jamais été acké), le système a
coupé, et le `connect failed` suivant n'a **pas reprogrammé de retry**. Règle du
CLAUDE.md ("never trust restored connection state without a live write") n'est
appliquée qu'à moitié : on détecte l'écriture qui échoue, mais après `connect failed`
il n'y a aucun backoff-retry qui repart.

**Niveau 2 — pas de keepalive pendant le background.** Entre 23:45:25 et 07:33,
l'app n'émet RIEN pendant des heures. iOS a suspendu le process (le mode
`bluetooth-central` ne protège que tant qu'une session est réellement active).
À chaque relance (01:53, 03:24) l'app retombe sur `already connected` (état
restauré/mis en cache) et ne tente jamais d'écriture de vérification → elle reste
convaincue que tout va bien.

## Facteur aggravant : drops de réassemblage massifs (61080005)

- **46 837 notifications "reassembly.dropped" en 24 h**, quasi toutes sur
  `61080005` (le char data), avec `dropped=244` systématique (468× juste
  après 17:00). Cela veut dire que le buffer de réassemblage sature et jette
  des paquets **pendant que la connexion est saine**.
- Après la stabilisation de ~18:26 le 09/08, les drops tombent à ~30/30 min et
  les pulse frames doublent → il y a eu un vrai mieux (probablement la charge
  système qui a baissé), mais le pattern reste.
- Piste : le traitement des notifications `61080005` bloque trop longtemps
  (décodage en Python-bridge? écriture DB sync?) → la queue CoreBluetooth
  déborde. Chaque drop = perte de données temps réel même quand "connecté".

## Ce que ça implique pour la roadmap (priorisé)

1. **[P0] Retry inconditionnel après `connect failed`.** Toute terminaison
   d'une tentative (succès OU échec) doit reprogrammer une tentative avec
   backoff expo (5 s → 60 s max), **y compris en background** — sinon le
   scénario "23:45 → 07:33" se reproduit chaque nuit.
2. **[P0] Write de vérification sur restauration.** Quand l'état restauré dit
   "connected/ready", faire un write réel (GET_BATTERY cmd 26) immédiatement ;
   si erreur → forcer un vrai disconnect + reconnect. Ne JAMAIS laisser
   `reconnect.state=already connected` sans preuve d'écriture.
3. **[P1] Chasser les drops 61080005.** Mesurer le temps de traitement d'une
   notification (title existant : `rust.bridge.timing`) et déplacer le décodage
   hors du callback CoreBluetooth si > 5 ms.
4. **[P1] Le backfill nocturne est VITAL pour ces fenêtres** — mais il ne marche
   pas encore (voir point suivant).

## Rappel : backfill toujours cassé (inchangé depuis hier)

- `history_sample` = **0 lignes** ; 1 seul frame type-47 depuis le 07/09 (test
  Atria de 20:34, vide). Le bracelet répond "rien en mémoire" à chaque fois.
- **Incohérence à résoudre** : la nuit du 07 au 08 il y avait pourtant ~8 h de
  gap réel. Si le bracelet bufférisait l'HR, cmd22 aurait dû rendre quelque
  chose. Conclusion actuelle : soit le buffer n'est PAS alimenté en mode
  streaming (hypothèse Atria déjà testée : non — test 20:34 avec realtime
  coupé = toujours vide), soit nos commandes 34/22 ne correspondent pas au
  firmware. Le 23/07 (seul succès : 580 frames) reste la seule preuve que ça
  peut marcher — comparer les frames cmd34/22 exactes du 23/07 avec celles
  d'aujourd'hui est LA prochaine étape protocolaire.

## Recommandation opérationnelle immédiate (sans rebuild)

Tant que les P0 ne sont pas livrés : **lancer l'app avant de dormir** (une ouverture
au premier plan + 10 s relance le process et la machine de reconnect), et la
laisser branchée en charge — les deux mortes nocturnes ont commencé pendant que le
téléphone était posé, écran éteint, à 15 % de batterie.

---
*Généré automatiquement pendant la nuit par Hermes (session locale, Mac).
Requêtes reproductibles : `ssh root@VPS docker exec -i whoop-api python3 -` avec
psycopg sur `$DATABASE_URL` (voir CLAUDE.md "Live debugging").*
