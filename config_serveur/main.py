"""Serveur de sauvegarde AKIBA — multi-utilisateurs.

Deux modes, sans changer l'application :

* **Jeton partagé (recommandé, le plus simple)** — une seule valeur dans
  ``SHARED_TOKEN``. Chaque personne écrit ``JETON:son_nom`` dans le champ
  « Jeton d'accès » d'AKIBA ; le serveur reconnaît le jeton, puis range la
  sauvegarde dans ``/data/backups/<son_nom>/``. Sans nom (``JETON`` seul),
  tout va dans ``default``.
* **Jeton dédié par personne (facultatif)** — ``USER_TOKENS`` au format
  ``jeton:utilisateur,jeton2:utilisateur2`` : chaque jeton ouvre alors son
  propre dossier, sans avoir à saisir de nom.

Ces deux formes se combinent. Le client AKIBA n'envoie que l'enveloppe JSON
déjà chiffrée (AES-256-GCM) : ce serveur ne la déchiffre jamais, ne la modifie
jamais et la rend telle quelle.

Compatibilité : si ni ``SHARED_TOKEN`` ni ``USER_TOKENS`` ne sont définis,
``API_TOKEN`` sert de jeton partagé (dossier ``default`` si aucun nom).

Endpoints :

* ``GET  /`` et ``GET /backup``  → dernière enveloppe brute, **404** si vide.
* ``PUT  /`` et ``PUT /backup``  → enregistre l'enveloppe brute.
* ``GET  /health``               → état + utilisateur authentifié.
* ``GET  /ping``                 → vivacité, sans jeton (healthcheck Docker).
"""

from __future__ import annotations

import json
import os
import re
import secrets
import shutil
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import Response

DATA_DIR = Path(os.getenv("BACKUP_DIR", "/data/backups"))
LATEST_NAME = "latest.json"
HISTORY_NAME = "history"
MAX_HISTORY = 30
AKIBA_FORMAT = "akiba-backup"
MAX_BODY_BYTES = 32 * 1024 * 1024

app = FastAPI(title="AKIBA Backup Server", version="2.0.0")

_UNSAFE = re.compile(r"[^A-Za-z0-9_-]+")

# Guillemets et espaces souvent copiés depuis un YAML ou un message.
_QUOTES = " \t\r\n\"'\u201c\u201d\u2018\u2019"


def clean_token(raw: str) -> str:
    """Jeton sans espaces ni guillemets collés autour.

    Copier ``SHARED_TOKEN: "abc123"`` ou un jeton depuis un message ajoute
    souvent des guillemets, un espace ou un saut de ligne : le serveur
    répondait alors 401 alors que le jeton était le bon.
    """
    return (raw or "").strip(_QUOTES)


def safe_username(raw: str) -> str:
    """Nom de dossier sûr : lettres, chiffres, tiret et souligné."""
    cleaned = _UNSAFE.sub("_", (raw or "").strip()).strip("_")
    cleaned = cleaned[:64]
    if cleaned in ("", ".", ".."):
        return "default"
    return cleaned


DEFAULT_USER = "default"


def load_config() -> tuple[dict[str, str], str]:
    """(jetons dédiés, jeton partagé).

    ``USER_TOKENS`` accepte les deux formes : ``jeton:utilisateur`` (jeton
    dédié) et ``jeton`` seul (jeton partagé, l'utilisateur étant alors donné
    par le client sous la forme ``jeton:nom``). ``SHARED_TOKEN`` force le jeton
    partagé et prime sur la forme courte de ``USER_TOKENS``.
    """
    dedicated: dict[str, str] = {}
    shared = ""
    raw = os.getenv("USER_TOKENS", "").strip()
    for entry in raw.split(","):
        entry = clean_token(entry)
        if not entry:
            continue
        if ":" not in entry:
            shared = entry
            continue
        token, user = entry.split(":", 1)
        token, user = clean_token(token), user.strip()
        if token and user:
            dedicated[token] = safe_username(user)
    explicit = clean_token(os.getenv("SHARED_TOKEN", ""))
    if explicit:
        shared = explicit
    if not shared and not dedicated:
        shared = clean_token(os.getenv("API_TOKEN", ""))
    return dedicated, shared


TOKENS, SHARED_TOKEN = load_config()


def _same(left: str, right: str) -> bool:
    """Comparaison à temps constant, même avec des accents dans le nom.

    ``secrets.compare_digest`` refuse les ``str`` non ASCII (TypeError) : un
    nom saisi avec un accent provoquerait une erreur 500. On compare donc des
    octets UTF-8.
    """
    return secrets.compare_digest(left.encode("utf-8"), right.encode("utf-8"))


def _shared_user(token: str) -> str | None:
    """Utilisateur désigné par ``JETON:nom`` (ou ``JETON/nom``), sinon None."""
    if not SHARED_TOKEN:
        return None
    if _same(SHARED_TOKEN, token):
        return DEFAULT_USER
    for separator in (":", "/"):
        if separator not in token:
            continue
        base, suffix = token.split(separator, 1)
        if not _same(clean_token(base), SHARED_TOKEN):
            continue
        suffix = clean_token(suffix)
        # Un nom vide retombe sur le dossier partagé « default ».
        return safe_username(suffix) if suffix else DEFAULT_USER
    return None


def authenticate(authorization: str | None) -> str:
    """Retourne l'utilisateur du jeton, ou lève 401."""
    if not TOKENS and not SHARED_TOKEN:
        raise HTTPException(
            status_code=500,
            detail=(
                "Aucun jeton configuré : renseignez SHARED_TOKEN "
                "(ou USER_TOKENS)."
            ),
        )
    if not authorization:
        raise HTTPException(
            status_code=401,
            detail="Jeton manquant : AKIBA n’a envoyé aucun jeton.",
        )
    parts = authorization.strip().split(" ", 1)
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(
            status_code=401,
            detail="En-tête Authorization invalide (Bearer attendu).",
        )
    token = clean_token(parts[1])
    for candidate, user in TOKENS.items():
        if _same(candidate, token):
            return user
    shared_user = _shared_user(token)
    if shared_user is not None:
        return shared_user
    raise HTTPException(
        status_code=401,
        detail=(
            "Jeton invalide. Vérifiez SHARED_TOKEN dans docker-compose.yml, "
            "puis recréez le conteneur (docker compose up -d : un simple "
            "redémarrage ne recharge pas les variables d’environnement)."
        ),
    )


def user_dir(user: str) -> Path:
    folder = DATA_DIR / safe_username(user)
    folder.mkdir(parents=True, exist_ok=True)
    return folder


def load_latest(user: str) -> bytes | None:
    path = user_dir(user) / LATEST_NAME
    if not path.is_file():
        return None
    return path.read_bytes()


def _write_atomic(target: Path, data: bytes) -> None:
    """Écrit puis remplace : jamais de fichier à moitié écrit."""
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(f".{target.name}.part")
    with open(temporary, "wb") as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, target)


def _prune_history(folder: Path) -> None:
    if not folder.is_dir():
        return
    files = [item for item in folder.iterdir() if item.is_file()]
    files.sort(key=lambda item: item.stat().st_mtime)
    while len(files) > MAX_HISTORY:
        oldest = files.pop(0)
        try:
            oldest.unlink()
        except OSError:
            pass


def migrate_legacy_backup() -> None:
    """Reprend l'ancien ``latest_backup.bin`` unique dans le dossier default."""
    legacy = DATA_DIR / "latest_backup.bin"
    if not legacy.is_file():
        return
    target = DATA_DIR / "default" / LATEST_NAME
    if target.exists():
        return
    try:
        _write_atomic(target, legacy.read_bytes())
    except OSError:
        pass


try:
    migrate_legacy_backup()
except OSError:
    pass


@app.get("/ping")
async def ping() -> dict[str, str]:
    """Vivacité sans jeton : ne révèle aucune donnée."""
    return {"status": "ok"}


@app.get("/health")
async def health(authorization: str | None = Header(None)) -> dict[str, object]:
    user = authenticate(authorization)
    latest = user_dir(user) / LATEST_NAME
    size = latest.stat().st_size if latest.is_file() else 0
    return {
        "status": "ok",
        "user": user,
        "shared_token": bool(SHARED_TOKEN),
        "backup_available": latest.is_file(),
        "backup_bytes": size,
        "format": AKIBA_FORMAT,
    }


@app.get("/")
@app.get("/backup")
async def get_backup(authorization: str | None = Header(None)) -> Response:
    """Rend l'enveloppe **brute**, sans réencodage. 404 : aucune sauvegarde."""
    user = authenticate(authorization)
    data = load_latest(user)
    if data is None:
        raise HTTPException(
            status_code=404,
            detail="Aucune sauvegarde pour cet utilisateur.",
        )
    return Response(
        content=data,
        media_type="application/json",
        headers={
            "X-Akiba-Backup-User": user,
            "X-Akiba-Backup-Format": AKIBA_FORMAT,
            "Cache-Control": "no-store",
        },
    )


@app.put("/")
@app.put("/backup")
async def put_backup(
    request: Request,
    authorization: str | None = Header(None),
) -> dict[str, object]:
    """Enregistre l'enveloppe telle qu'elle arrive (dernière + historique)."""
    user = authenticate(authorization)
    body = await request.body()
    if not body:
        raise HTTPException(status_code=400, detail="Sauvegarde vide.")
    if len(body) > MAX_BODY_BYTES:
        raise HTTPException(status_code=413, detail="Sauvegarde trop volumineuse.")

    try:
        payload = json.loads(body)
    except (ValueError, UnicodeDecodeError):
        raise HTTPException(
            status_code=400,
            detail="Le corps n'est pas un JSON valide.",
        )
    if not isinstance(payload, dict) or payload.get("format") != AKIBA_FORMAT:
        raise HTTPException(
            status_code=400,
            detail="Ce JSON n'est pas une enveloppe de sauvegarde AKIBA.",
        )

    folder = user_dir(user)
    latest = folder / LATEST_NAME
    _write_atomic(latest, body)

    history = folder / HISTORY_NAME
    history.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    _write_atomic(history / f"backup_{stamp}.json", body)
    _prune_history(history)

    return {
        "status": "success",
        "user": user,
        "bytes_saved": len(body),
        "saved_at": datetime.now(timezone.utc).isoformat(),
    }
