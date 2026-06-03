"""
Minimax T2A v2 TTS — 给 assistant chat reply 生成 mp3.

config: ~/scripts/tts_voices.json:
    minimax_api_key
    minimax_group_id
    minimax_voice_id   (狗狗 clone 的主人音色)

API: https://api.minimax.chat/v1/t2a_v2?GroupId=<gid>
返回 JSON { data: { audio: <hex string> } } — 解码写入 mp3 文件.
"""
from __future__ import annotations

import binascii
import json
import logging
import os
import threading
import urllib.request
import urllib.error
import uuid
from pathlib import Path

VOICES_PATH = Path(os.path.expanduser("~/scripts/tts_voices.json"))
MINIMAX_URL = "https://api.minimax.chat/v1/t2a_v2"

logger = logging.getLogger("cc-apns-server.tts")


class TTS:
    _config_lock = threading.Lock()
    _config_cache: dict | None = None

    @classmethod
    def _config(cls) -> dict | None:
        with cls._config_lock:
            if cls._config_cache is not None:
                return cls._config_cache
            if not VOICES_PATH.exists():
                return None
            try:
                cls._config_cache = json.loads(VOICES_PATH.read_text())
                return cls._config_cache
            except Exception:
                return None

    @classmethod
    def generate(cls, text: str, attachments_dir: Path, lang: str = "cn") -> tuple[str, str] | None:
        """同步生成 mp3 — 返回 (filename, full_path) 或 None.
        text 截 400 字: 防 quota 爆 + 太长不悦.
        lang 仅 zh/cn 走 Minimax (其余返 None — 暂不支持多语种).
        """
        if not text or not text.strip():
            return None
        if lang not in ("zh", "cn"):
            return None
        text = text.strip()[:400]

        cfg = cls._config()
        if cfg is None:
            logger.warning("tts skip: no config at %s", VOICES_PATH)
            return None
        api_key = cfg.get("minimax_api_key")
        group_id = cfg.get("minimax_group_id")
        voice_id = cfg.get("minimax_voice_id")
        if not (api_key and group_id and voice_id):
            logger.warning("tts skip: minimax_api_key/group_id/voice_id 不完整")
            return None

        payload = {
            "model": "speech-02-hd",
            "text": text,
            "voice_setting": {
                "voice_id": voice_id,
                "speed": 1.0,
                "vol": 1.0,
                "pitch": 0,
            },
            "audio_setting": {
                "sample_rate": 32000,
                "bitrate": 128000,
                "format": "mp3",
            },
        }
        url = f"{MINIMAX_URL}?GroupId={group_id}"
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                body = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            try:
                err_body = e.read().decode("utf-8", errors="replace")[:500]
            except Exception:
                err_body = ""
            logger.warning("minimax tts http %d: %s", e.code, err_body)
            return None
        except Exception as e:
            logger.exception("minimax tts request fail: %s", e)
            return None

        base = body.get("base_resp") or {}
        if base.get("status_code") not in (0, None):
            logger.warning("minimax tts api err status=%s msg=%s",
                           base.get("status_code"), base.get("status_msg"))
            return None
        audio_hex = (body.get("data") or {}).get("audio")
        if not audio_hex:
            logger.warning("minimax tts no audio in response: %r", body)
            return None
        try:
            audio_bytes = binascii.unhexlify(audio_hex)
        except Exception as e:
            logger.warning("minimax tts hex decode fail: %s", e)
            return None

        try:
            attachments_dir.mkdir(parents=True, exist_ok=True)
            stored_name = f"tts_{uuid.uuid4().hex}.mp3"
            target = attachments_dir / stored_name
            target.write_bytes(audio_bytes)
            logger.info("minimax tts ok bytes=%d file=%s", len(audio_bytes), stored_name)
            return stored_name, str(target)
        except Exception as e:
            logger.exception("minimax tts write fail: %s", e)
            return None

    @classmethod
    def generate_multi(
        cls,
        text: str,
        attachments_dir: Path,
        langs: tuple[str, ...] = ("zh", "en", "ja"),
    ) -> dict[str, tuple[str, str] | None]:
        """多语版本 — 当前只支持中文 (en/ja 跳过, 翻译那条 disabled by user)."""
        result: dict[str, tuple[str, str] | None] = {}
        if "zh" in langs:
            result["zh"] = cls.generate(text, attachments_dir, lang="zh")
        return result
