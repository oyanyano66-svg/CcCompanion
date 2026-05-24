"""
Fish Audio 龙皓晨 TTS — 给 assistant chat reply 生成 mp3.

config: ~/scripts/tts_voices.json — fish_audio_api_key + voices.cn.id
"""
from __future__ import annotations

import json
import os
import threading
import uuid
import concurrent.futures
import subprocess
from pathlib import Path

VOICES_PATH = Path(os.path.expanduser("~/scripts/tts_voices.json"))


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
        """同步生成 mp3 文件 — 返回 (filename, full_path) 或 None
        text 截 400 字 防 fish audio quota 爆 + 太长不悦
        """
        import logging
        logger = logging.getLogger("cc-apns-server.tts")
        if not text or not text.strip():
            logger.warning("tts skip: empty text")
            return None
        text = text.strip()[:400]
        cfg = cls._config()
        if cfg is None:
            logger.warning("tts skip: no config at %s", VOICES_PATH)
            return None
        api_key = cfg.get("fish_audio_api_key")
        voices = cfg.get("voices", {})
        voice = voices.get(lang) or voices.get("cn")
        if not api_key or not voice:
            logger.warning("tts skip: missing api_key or voice")
            return None
        try:
            from fish_audio_sdk import Session, TTSRequest
        except ImportError as e:
            logger.warning("tts skip: fish_audio_sdk import fail: %s", e)
            return None
        try:
            attachments_dir.mkdir(parents=True, exist_ok=True)
            stored_name = f"tts_{uuid.uuid4().hex}.mp3"
            target = attachments_dir / stored_name
            session = Session(api_key)
            with target.open("wb") as f:
                for chunk in session.tts(TTSRequest(
                    text=text,
                    reference_id=voice["id"],
                    format="mp3",
                )):
                    f.write(chunk)
            return stored_name, str(target)
        except Exception as e:
            logger.exception("tts api fail: %s", e)
            return None

    @classmethod
    def generate_multi(
        cls,
        text: str,
        attachments_dir: Path,
        langs: tuple[str, ...] = ("zh", "en", "ja"),
    ) -> dict[str, tuple[str, str] | None]:
        """同步生成多语 mp3. zh 直接用 cn voice, en/ja 先翻译再生成."""
        result: dict[str, tuple[str, str] | None] = {}
        if "zh" in langs:
            result["zh"] = cls.generate(text, attachments_dir, lang="cn")

        translate_langs = [lang for lang in ("en", "ja") if lang in langs]
        if not translate_langs:
            return result

        voice_keys = {"en": "en", "ja": "jp"}
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
            futures = {lang: ex.submit(cls._translate, text, lang) for lang in translate_langs}
            for lang, fut in futures.items():
                try:
                    translated = fut.result(timeout=60)
                except Exception:
                    translated = None
                if translated:
                    result[lang] = cls.generate(translated, attachments_dir, lang=voice_keys[lang])
                else:
                    result[lang] = None
        return result

    @classmethod
    def _translate(cls, text: str, target: str) -> str | None:
        """Translation disabled — used to spawn `claude --print` subprocesses; user
        does not want any headless `claude -p`/`--print` invocations. Returns None
        so multi-lang TTS falls back to the original Chinese (or skips that lang)."""
        import logging
        logger = logging.getLogger("cc-apns-server.tts")
        logger.info("translate disabled (no claude --print) target=%s len=%d", target, len(text) if text else 0)
        return None

