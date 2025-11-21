"""Ollama API連携モジュール"""
import requests
import json
from typing import List, Dict
from .config import Config


class OllamaClient:
    """Ollamaとの連携を管理するクライアント"""

    def __init__(self):
        self.url = Config.OLLAMA_URL
        self.model = Config.OLLAMA_MODEL
        self.conversation_history: List[Dict[str, str]] = []
        self.max_history = Config.MAX_CONVERSATION_HISTORY

    def generate_response(self, user_message: str, is_idle_chat: bool = False) -> str:
        """
        ユーザーメッセージに対する応答を生成

        Args:
            user_message: ユーザーからのメッセージ
            is_idle_chat: 雑談モードかどうか

        Returns:
            生成された応答テキスト
        """
        try:
            # システムプロンプトの作成
            if is_idle_chat:
                system_prompt = (
                    "あなたは24時間配信ラジオのパーソナリティです。"
                    "リスナーからのコメントがないので、これまでの会話の流れに沿って、"
                    "自然な雑談をしてください。短く簡潔に話してください。"
                )
            else:
                system_prompt = (
                    "あなたは24時間配信ラジオのパーソナリティです。"
                    "リスナーからのコメントに親しみやすく答えてください。"
                    "短く簡潔に話してください。"
                )

            # メッセージの構築
            messages = [{"role": "system", "content": system_prompt}]

            # 会話履歴を追加
            for msg in self.conversation_history:
                messages.append(msg)

            # 新しいメッセージを追加
            if not is_idle_chat:
                messages.append({"role": "user", "content": user_message})

            # Ollama APIを呼び出し
            response = requests.post(
                f"{self.url}/api/chat",
                json={
                    "model": self.model,
                    "messages": messages,
                    "stream": False
                },
                timeout=30
            )

            response.raise_for_status()
            result = response.json()

            # 応答テキストを取得
            assistant_message = result.get("message", {}).get("content", "")

            # 会話履歴に追加
            if not is_idle_chat:
                self.conversation_history.append({"role": "user", "content": user_message})

            self.conversation_history.append({"role": "assistant", "content": assistant_message})

            # 履歴が最大数を超えたら古いものから削除（システムメッセージを除く）
            while len(self.conversation_history) > self.max_history:
                self.conversation_history.pop(0)

            return assistant_message

        except requests.exceptions.RequestException as e:
            print(f"Ollama API エラー: {e}")
            return "申し訳ありません、現在応答できません。"

    def generate_idle_chat(self) -> str:
        """
        コメントがない時の雑談を生成

        Returns:
            生成された雑談テキスト
        """
        # 会話履歴がある場合は文脈に沿った雑談を生成
        if self.conversation_history:
            prompt = "これまでの話題に関連することを少し話してください。"
        else:
            prompt = "自己紹介や今日の天気など、自然な話題で話し始めてください。"

        return self.generate_response(prompt, is_idle_chat=True)

    def reset_history(self):
        """会話履歴をリセット"""
        self.conversation_history = []
