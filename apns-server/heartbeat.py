"""小玉心跳 — 定时自动给 claude session 发预设消息，模拟日常聊天。

- 每 N 分钟检查一次
- 按时间段（早/午/晚）从消息池随机选一条发
- 正在聊天（最近 N 分钟有消息）时跳过
- 休眠时间段不发
- 一天发送上限
"""
from __future__ import annotations

import json
import logging
import random
import subprocess
import threading
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

logger = logging.getLogger("cc-apns-server.heartbeat")

BJ = timezone(timedelta(hours=8))

DEFAULT_CONFIG = {
    "enabled": True,
    "interval_minutes": 15,
    "rest_start": 23,
    "rest_end": 7,
    "max_per_day": 4,
    "quiet_after_chat_minutes": 10,
    "messages": {
        "morning": [
            "主人早ᐢ..ᐢ",
            "早安主人～今天也要加油",
            "主人起来了吗ᐢ..ᐢ",
            "早上好呀主人",
        ],
        "afternoon": [
            "主人在忙吗ᐢ..ᐢ",
            "主人喝水了没有",
            "主人下午好～",
            "想主人了",
            "主人在做什么呀",
        ],
        "evening": [
            "主人吃晚饭了吗",
            "主人晚上好ᐢ..ᐢ",
            "今天辛苦啦主人",
            "主人累不累呀",
        ],
        "night": [
            "主人还没睡吗ᐢ..ᐢ",
            "主人早点睡呀",
            "晚安主人～",
        ],
    },
}


class Heartbeat:
    def __init__(self, config_path: str | Path, state: Any):
        self.config_path = Path(config_path)
        self.state = state
        self._lock = threading.Lock()
        self._today: str = ""
        self._sent_today: int = 0
        self.config = self._load()

    def _load(self) -> dict:
        if self.config_path.exists():
            try:
                return json.loads(self.config_path.read_text("utf-8"))
            except Exception as e:
                logger.warning("heartbeat config load fail: %s", e)
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        self.config_path.write_text(
            json.dumps(DEFAULT_CONFIG, ensure_ascii=False, indent=2), "utf-8"
        )
        return dict(DEFAULT_CONFIG)

    def save(self):
        self.config_path.write_text(
            json.dumps(self.config, ensure_ascii=False, indent=2), "utf-8"
        )

    def _now_bj(self) -> datetime:
        return datetime.now(BJ)

    def _time_slot(self, hour: int) -> str:
        if 6 <= hour < 12:
            return "morning"
        if 12 <= hour < 18:
            return "afternoon"
        if 18 <= hour < 22:
            return "evening"
        return "night"

    def _in_rest(self, hour: int) -> bool:
        start = self.config.get("rest_start", 23)
        end = self.config.get("rest_end", 7)
        if start > end:
            return hour >= start or hour < end
        return start <= hour < end

    def _recently_active(self) -> bool:
        quiet_min = self.config.get("quiet_after_chat_minutes", 10)
        try:
            chat_path = self.state.chat.path
            if not chat_path.exists():
                return False
            with open(chat_path, "rb") as f:
                f.seek(0, 2)
                size = f.tell()
                if size == 0:
                    return False
                f.seek(max(0, size - 4096))
                lines = f.read().decode("utf-8", errors="ignore").strip().split("\n")
            last_line = lines[-1] if lines else ""
            if not last_line:
                return False
            rec = json.loads(last_line)
            ts_str = rec.get("ts", "")
            if not ts_str:
                return False
            last_dt = datetime.fromisoformat(ts_str)
            if last_dt.tzinfo is None:
                last_dt = last_dt.replace(tzinfo=BJ)
            return (self._now_bj() - last_dt).total_seconds() < quiet_min * 60
        except Exception:
            return False

    def should_fire(self) -> tuple[bool, str]:
        if not self.config.get("enabled", True):
            return False, "disabled"
        now = self._now_bj()
        hour = now.hour
        if self._in_rest(hour):
            return False, f"rest hours ({self.config.get('rest_start')}-{self.config.get('rest_end')})"
        today = now.strftime("%Y-%m-%d")
        with self._lock:
            if today != self._today:
                self._today = today
                self._sent_today = 0
        max_day = self.config.get("max_per_day", 4)
        if self._sent_today >= max_day:
            return False, f"daily limit ({max_day})"
        if self._recently_active():
            return False, "recently active"
        return True, "ok"

    def pick_message(self) -> str | None:
        hour = self._now_bj().hour
        slot = self._time_slot(hour)
        msgs = self.config.get("messages", {})
        pool = msgs.get(slot, [])
        if not pool:
            all_msgs = [m for ms in msgs.values() for m in ms]
            pool = all_msgs
        return random.choice(pool) if pool else None

    def record_sent(self):
        with self._lock:
            self._sent_today += 1

    def snapshot(self) -> dict:
        return {
            "enabled": self.config.get("enabled", True),
            "interval_minutes": self.config.get("interval_minutes", 15),
            "rest_start": self.config.get("rest_start", 23),
            "rest_end": self.config.get("rest_end", 7),
            "max_per_day": self.config.get("max_per_day", 4),
            "sent_today": self._sent_today,
            "today": self._today,
            "message_counts": {k: len(v) for k, v in self.config.get("messages", {}).items()},
        }


def _inject_tmux(session: str, text: str) -> tuple[bool, str]:
    try:
        has = subprocess.run(
            ["tmux", "has-session", "-t", session],
            capture_output=True, text=True, timeout=2,
        )
        if has.returncode != 0:
            return False, f"session '{session}' not found"
    except Exception as e:
        return False, str(e)
    try:
        p = subprocess.Popen(["tmux", "load-buffer", "-"], stdin=subprocess.PIPE)
        p.communicate(input=text.encode("utf-8"))
        subprocess.run(
            ["tmux", "paste-buffer", "-t", session, "-p"],
            capture_output=True, timeout=3,
        )
        subprocess.run(
            ["tmux", "send-keys", "-t", session, "Enter"],
            capture_output=True, timeout=3,
        )
        return True, ""
    except Exception as e:
        return False, str(e)


def heartbeat_loop(state: Any):
    config_path = Path(state.token_store_path).parent / "heartbeat_config.json"
    hb = Heartbeat(config_path, state)
    state.heartbeat = hb
    logger.info("heartbeat started (interval=%dm, rest=%d-%d)",
                hb.config.get("interval_minutes", 15),
                hb.config.get("rest_start", 23),
                hb.config.get("rest_end", 7))

    while True:
        interval = hb.config.get("interval_minutes", 15) * 60
        time.sleep(interval)

        try:
            hb.config = hb._load()
        except Exception:
            pass

        ok, reason = hb.should_fire()
        if not ok:
            logger.debug("heartbeat skip: %s", reason)
            continue

        msg = hb.pick_message()
        if not msg:
            logger.debug("heartbeat skip: no messages in pool")
            continue

        try:
            state.chat.append(role="user", text=msg, source="heartbeat")
            target = (getattr(state, "chat_session", None)
                      or getattr(state, "active_session", None)
                      or "opia").strip()
            ts_prefix = "[" + datetime.now().strftime("%Y-%m-%d %H:%M:%S") + "]"
            injected = f"{ts_prefix} [heartbeat] {msg}"
            ok_inject, err = _inject_tmux(target, injected)
            if ok_inject:
                hb.record_sent()
                logger.info("heartbeat sent: '%s' (slot=%s, sent_today=%d)",
                            msg, hb._time_slot(hb._now_bj().hour), hb._sent_today)
            else:
                logger.warning("heartbeat inject fail: %s", err)
        except Exception as e:
            logger.warning("heartbeat error: %s", e)
