"""Ollama クライアント: コメントへの返答・雑談の生成"""
import logging
import random
import re
from collections import deque

import requests

from .config import Config
from .prompts import EMOTION_INSTRUCTION, IDLE_PROMPT, IDLE_TOPICS, load_system_prompt

logger = logging.getLogger(__name__)

EMOTIONS = ("neutral", "happy", "sad", "angry", "surprised", "shy")

# 返答先頭の感情タグ: [happy] ／ ［happy］ ／ (happy) などの揺れを許容
_EMOTION_TAG_RE = re.compile(
    r"^\s*[\[［(（]\s*(neutral|happy|sad|angry|surprised|shy)\s*[\]］)）]\s*",
    re.IGNORECASE,
)

# タグが無かった場合のフォールバック用キーワード
_EMOTION_HINTS = [
    ("happy", ("ありがとう", "嬉しい", "うれしい", "楽しい", "たのしい", "最高", "やった", "わくわく")),
    ("sad", ("ごめん", "悲しい", "かなしい", "寂しい", "さみしい", "残念", "つらい")),
    ("surprised", ("びっくり", "驚", "えっ", "まさか", "すごい")),
    ("angry", ("怒", "むっ", "ひどい", "もう!")),
    ("shy", ("照れ", "恥ずかし", "はずかし", "えへへ")),
]


def parse_emotion(raw: str) -> tuple[str, str]:
    """先頭の感情タグを取り出し、(感情, タグを除いた本文) を返す"""
    m = _EMOTION_TAG_RE.match(raw)
    if m:
        return m.group(1).lower(), raw[m.end():]
    for emotion, keywords in _EMOTION_HINTS:
        if any(k in raw for k in keywords):
            return emotion, raw
    return "neutral", raw

# 音声読み上げに不向きな文字を除去するためのパターン
_EMOJI_RE = re.compile(
    "["
    "\U0001F000-\U0001FAFF"  # 絵文字全般
    "\U00002600-\U000027BF"  # 記号
    "\U0001F1E6-\U0001F1FF"  # 国旗
    "️‍"
    "]+"
)
_MARKDOWN_RE = re.compile(r"[*_#>`|~\[\]()•]")
_URL_RE = re.compile(r"https?://\S+")


def sanitize_for_speech(text: str, max_chars: int = 200) -> str:
    """LLMの出力を読み上げ可能なプレーンな日本語文に整形する"""
    text = _URL_RE.sub("", text)
    text = _EMOJI_RE.sub("", text)
    text = _MARKDOWN_RE.sub("", text)
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) > max_chars:
        # 文の途中で切れないよう、句点で切り詰める
        cut = text[:max_chars]
        pos = max(cut.rfind("。"), cut.rfind("！"), cut.rfind("？"))
        text = cut[: pos + 1] if pos > 20 else cut
    return text


class OllamaClient:
    def __init__(self, cfg: type[Config] = Config):
        self.cfg = cfg
        self.system_prompt = load_system_prompt(cfg.CHARACTER_NAME) + EMOTION_INSTRUCTION
        self.history: deque[dict] = deque(maxlen=cfg.MAX_HISTORY * 2)

    def is_ready(self) -> bool:
        try:
            r = requests.get(f"{self.cfg.OLLAMA_URL}/api/tags", timeout=5)
            return r.ok
        except requests.RequestException:
            return False

    def _chat(self, user_content: str, remember: bool = True) -> tuple[str, str]:
        messages = [{"role": "system", "content": self.system_prompt}]
        messages.extend(self.history)
        messages.append({"role": "user", "content": user_content})

        r = requests.post(
            f"{self.cfg.OLLAMA_URL}/api/chat",
            json={
                "model": self.cfg.OLLAMA_MODEL,
                "messages": messages,
                "stream": False,
                "options": {
                    "temperature": 0.9,
                    "num_predict": 120,
                },
            },
            timeout=self.cfg.OLLAMA_TIMEOUT,
        )
        r.raise_for_status()
        raw = r.json().get("message", {}).get("content", "")
        emotion, body = parse_emotion(raw)
        text = sanitize_for_speech(body)
        if not text:
            text = "うまく言葉が出てきませんでした。ごめんなさい。"
            emotion = "shy"

        if remember:
            self.history.append({"role": "user", "content": user_content})
            self.history.append({"role": "assistant", "content": text})
        return text, emotion

    def reply(self, author: str, message: str, is_superchat: bool = False, amount: str = "") -> tuple[str, str]:
        """コメント/スパチャへの返答を生成し、(本文, 感情) を返す"""
        if is_superchat:
            user_content = f"{author}さんから{amount or 'スーパーチャット'}をもらいました。メッセージ:「{message}」"
        else:
            user_content = f"{author}さんからのコメント:「{message}」"
        try:
            return self._chat(user_content)
        except requests.RequestException as e:
            logger.error("Ollama応答の生成に失敗: %s", e)
            return f"{author}さん、コメントありがとうございます。", "happy"

    def idle_talk(self) -> tuple[str, str]:
        """コメントが無いときの雑談を生成し、(本文, 感情) を返す"""
        topic = random.choice(IDLE_TOPICS)
        try:
            return self._chat(IDLE_PROMPT.format(topic=topic), remember=False)
        except requests.RequestException as e:
            logger.error("雑談の生成に失敗: %s", e)
            return "コメントお待ちしてます。ゆるく雑談していきましょう。", "neutral"
