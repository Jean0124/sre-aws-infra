"""
Lambda handler — Servicio de procesamiento con caché Redis y persistencia S3.

Flujo:
  1. Genera una cache key a partir del body del request
  2. Consulta Redis:
     - HIT  → retorna el valor cacheado con X-Cache: HIT
     - MISS → procesa, guarda en S3, escribe en Redis con TTL 60s, retorna X-Cache: MISS
"""

import hashlib
import json
import logging
import os
import uuid
from datetime import datetime, timezone

import boto3
import redis

# ─── CONFIGURACIÓN DE LOGGER ─────────────────────────────────────────────────
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ─── CLIENTES (inicializados fuera del handler para reutilizar entre invocaciones)
s3_client = boto3.client("s3")

_redis_client = None


def get_redis_client() -> redis.Redis:
    """Singleton para el cliente Redis — evita reconexiones en cada invocación."""
    global _redis_client
    if _redis_client is None:
        _redis_client = redis.Redis(
            host=os.environ["REDIS_HOST"],
            port=int(os.environ.get("REDIS_PORT", 6379)),
            decode_responses=True,
            socket_connect_timeout=3,
            socket_timeout=3,
        )
    return _redis_client


def build_cache_key(body: dict) -> str:
    """Genera una cache key determinista a partir del body del request."""
    canonical = json.dumps(body, sort_keys=True, ensure_ascii=False)
    return "result:" + hashlib.sha256(canonical.encode()).hexdigest()


def process_payload(body: dict) -> dict:
    """
    Lógica de procesamiento del request.
    Transforma el payload: invierte los valores string y calcula un hash del body completo.
    """
    processed = {}
    for key, value in body.items():
        if isinstance(value, str):
            processed[key] = value[::-1]  # inversión del string
        else:
            processed[key] = value

    body_hash = hashlib.md5(
        json.dumps(body, sort_keys=True).encode()
    ).hexdigest()

    return {
        "original": body,
        "processed": processed,
        "hash": body_hash,
        "processed_at": datetime.now(timezone.utc).isoformat(),
    }


def save_to_s3(result: dict, bucket: str) -> str:
    """Persiste el resultado en S3 bajo results/<fecha>/<uuid>.json."""
    now = datetime.now(timezone.utc)
    date_prefix = now.strftime("%Y-%m-%d")
    object_key = f"results/{date_prefix}/{uuid.uuid4()}.json"

    s3_client.put_object(
        Bucket=bucket,
        Key=object_key,
        Body=json.dumps(result, ensure_ascii=False),
        ContentType="application/json",
    )
    logger.info("Resultado guardado en S3: s3://%s/%s", bucket, object_key)
    return object_key


def build_response(status_code: int, body: dict, cache_status: str) -> dict:
    """Construye la respuesta HTTP con los headers requeridos."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "X-Cache": cache_status,
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Allow-Methods": "POST,OPTIONS",
        },
        "body": json.dumps(body, ensure_ascii=False),
    }


def handler(event: dict, context) -> dict:
    """Punto de entrada de la Lambda."""
    logger.info("Evento recibido: %s", json.dumps(event))

    # ── CORS preflight ────────────────────────────────────────────────────────
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return build_response(200, {}, "MISS")

    try:
        # ── Parsear body ──────────────────────────────────────────────────────
        raw_body = event.get("body") or "{}"
        if isinstance(raw_body, str):
            body = json.loads(raw_body)
        else:
            body = raw_body

        if not isinstance(body, dict):
            return build_response(
                400, {"error": "El body debe ser un objeto JSON válido"}, "MISS"
            )

        # ── Cache lookup ──────────────────────────────────────────────────────
        cache_key = build_cache_key(body)
        redis_client = get_redis_client()

        cached_value = redis_client.get(cache_key)

        if cached_value is not None:
            logger.info("Cache HIT para key: %s", cache_key)
            result = json.loads(cached_value)
            return build_response(200, result, "HIT")

        # ── Cache MISS: procesar ──────────────────────────────────────────────
        logger.info("Cache MISS para key: %s — procesando", cache_key)
        result = process_payload(body)

        # ── Persistir en S3 ───────────────────────────────────────────────────
        bucket_name = os.environ["S3_BUCKET_NAME"]
        s3_key = save_to_s3(result, bucket_name)
        result["s3_key"] = s3_key

        # ── Escribir en Redis con TTL de 60s ──────────────────────────────────
        redis_client.setex(cache_key, 60, json.dumps(result, ensure_ascii=False))
        logger.info("Resultado cacheado en Redis con TTL 60s. Key: %s", cache_key)

        return build_response(200, result, "MISS")

    except redis.RedisError as exc:
        logger.error("Error de Redis: %s", str(exc), exc_info=True)
        return build_response(500, {"error": f"Error de caché: {str(exc)}"}, "MISS")

    except Exception as exc:  # pylint: disable=broad-except
        logger.error("Error inesperado: %s", str(exc), exc_info=True)
        return build_response(
            500, {"error": f"Error interno del servidor: {str(exc)}"}, "MISS"
        )
