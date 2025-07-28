#!/usr/bin/env python3
"""
24時間ラジオライブ配信システム（Dockerなし版）
YouTube コメント → Ollama LLM → VOICEVOX → OBS配信

主な機能:
- YouTubeライブコメント・スーパーチャット自動取得
- Ollama + Gemma:1b による自然言語応答生成
- VOICEVOX ネイティブエンジンによる高品質音声合成
- 自動復旧機能付きの24時間連続運転
- リソース監視とパフォーマンス最適化
"""

import asyncio
import json
import logging
import subprocess
import time
import requests
import threading
import signal
import sys
import os
from queue import Queue, Empty
from typing import Optional, Dict, List
from datetime import datetime

# ログ設定
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/main_app.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class YouTubeCommentFetcher:
    """YouTubeライブコメント取得クラス"""
    
    def __init__(self, video_id: str, api_key: str):
        self.video_id = video_id
        self.api_key = api_key
        self.comment_queue = Queue()
        self.running = False
        self.live_chat_id = None
        self.next_page_token = None
        self.fetch_thread = None
        
    def start_fetching(self) -> bool:
        """コメント取得開始"""
        try:
            # ライブチャットIDを取得
            self.live_chat_id = self._get_live_chat_id()
            if not self.live_chat_id:
                logger.error("ライブチャットIDの取得に失敗しました")
                return False
                
            self.running = True
            self.fetch_thread = threading.Thread(target=self._fetch_comments, daemon=True)
            self.fetch_thread.start()
            logger.info("コメント取得開始")
            return True
            
        except Exception as e:
            logger.error(f"コメント取得開始エラー: {e}")
            return False
        
    def stop_fetching(self):
        """コメント取得停止"""
        self.running = False
        if self.fetch_thread:
            self.fetch_thread.join(timeout=5)
        logger.info("コメント取得停止")
        
    def _fetch_comments(self):
        """コメント取得ループ"""
        consecutive_errors = 0
        max_consecutive_errors = 5
        
        while self.running:
            try:
                # YouTube Live Chat Messages API呼び出し
                url = "https://www.googleapis.com/youtube/v3/liveChat/messages"
                params = {
                    'liveChatId': self.live_chat_id,
                    'part': 'snippet,authorDetails',
                    'key': self.api_key,
                    'maxResults': 200
                }
                
                if self.next_page_token:
                    params['pageToken'] = self.next_page_token
                
                response = requests.get(url, params=params, timeout=30)
                
                if response.status_code == 200:
                    data = response.json()
                    consecutive_errors = 0
                    
                    # 次のページトークン更新
                    self.next_page_token = data.get('nextPageToken')
                    
                    # ポーリング間隔の調整
                    polling_interval = data.get('pollingIntervalMillis', 5000) / 1000
                    
                    # コメント処理
                    if 'items' in data:
                        for item in data['items']:
                            comment_data = self._parse_comment(item)
                            if comment_data:
                                self.comment_queue.put(comment_data)
                                logger.info(f"新しいコメント: {comment_data['author']}: {comment_data['text']}")
                    
                    time.sleep(max(polling_interval, 2))
                    
                elif response.status_code == 403:
                    logger.error("API制限に達しました。しばらく待機します。")
                    time.sleep(60)
                    consecutive_errors += 1
                    
                else:
                    logger.error(f"API呼び出しエラー: {response.status_code}")
                    time.sleep(10)
                    consecutive_errors += 1
                
            except requests.exceptions.RequestException as e:
                logger.error(f"ネットワークエラー: {e}")
                consecutive_errors += 1
                time.sleep(15)
                
            except Exception as e:
                logger.error(f"コメント取得エラー: {e}")
                consecutive_errors += 1
                time.sleep(10)
            
            # 連続エラーが多い場合は長時間待機
            if consecutive_errors >= max_consecutive_errors:
                logger.warning(f"連続エラー{consecutive_errors}回。長時間待機します。")
                time.sleep(300)  # 5分待機
                consecutive_errors = 0
    
    def _get_live_chat_id(self) -> Optional[str]:
        """ライブチャットIDを取得"""
        try:
            url = "https://www.googleapis.com/youtube/v3/videos"
            params = {
                'part': 'liveStreamingDetails',
                'id': self.video_id,
                'key': self.api_key
            }
            
            response = requests.get(url, params=params, timeout=30)
            
            if response.status_code == 200:
                data = response.json()
                if 'items' in data and len(data['items']) > 0:
                    live_details = data['items'][0].get('liveStreamingDetails')
                    if live_details:
                        return live_details.get('activeLiveChatId')
            
            logger.error(f"ライブチャットID取得失敗: {response.status_code}")
            return None
            
        except Exception as e:
            logger.error(f"ライブチャットID取得エラー: {e}")
            return None
    
    def _parse_comment(self, item: Dict) -> Optional[Dict]:
        """コメントデータを解析"""
        try:
            snippet = item.get('snippet', {})
            author_details = item.get('authorDetails', {})
            
            # 基本情報
            comment_data = {
                'text': snippet.get('displayMessage', ''),
                'author': author_details.get('displayName', 'Unknown'),
                'timestamp': time.time(),
                'is_superchat': False,
                'superchat_amount': 0,
                'superchat_currency': '',
                'is_member': author_details.get('isChatSponsor', False),
                'is_moderator': author_details.get('isChatModerator', False),
                'is_owner': author_details.get('isChatOwner', False)
            }
            
            # スーパーチャット判定
            if 'superChatDetails' in snippet:
                comment_data['is_superchat'] = True
                superchat = snippet['superChatDetails']
                comment_data['superchat_amount'] = superchat.get('amountMicros', 0) / 1000000
                comment_data['superchat_currency'] = superchat.get('currency', '')
                
            # フィルタリング（空のコメントなど）
            if not comment_data['text'].strip():
                return None
                
            return comment_data
            
        except Exception as e:
            logger.error(f"コメント解析エラー: {e}")
            return None
    
    def get_comment(self) -> Optional[Dict]:
        """コメントを取得（非ブロッキング）"""
        try:
            return self.comment_queue.get_nowait()
        except Empty:
            return None
    
    def get_queue_size(self) -> int:
        """待機中のコメント数を取得"""
        return self.comment_queue.qsize()

class OllamaLLM:
    """Ollama LLMクラス"""
    
    def __init__(self, model_name: str = "gemma:1b", base_url: str = "http://localhost:11434"):
        self.model_name = model_name
        self.base_url = base_url
        self.conversation_history = []
        self.max_history_length = 10  # 会話履歴の最大保持数
        
    def generate_response(self, prompt: str, context: Optional[str] = None) -> str:
        """LLMからの応答を生成"""
        try:
            # システムプロンプト
            system_prompt = """あなたは24時間配信のラジオDJです。視聴者との親しみやすい会話を心がけ、自然で温かい応答をしてください。
            
特徴:
- 親しみやすく、フレンドリーな口調
- 適度な関西弁を織り交ぜる
- 短めの応答（1-2文程度）
- 感情豊かな表現
- 視聴者の名前を呼ぶ"""

            # コンテキストの構築
            full_prompt = f"{system_prompt}\n\n"
            
            if context:
                full_prompt += f"状況: {context}\n\n"
            
            # 会話履歴の追加（最新の数件のみ）
            if self.conversation_history:
                recent_history = self.conversation_history[-3:]  # 最新3件
                for entry in recent_history:
                    full_prompt += f"過去の会話: {entry}\n"
                full_prompt += "\n"
            
            full_prompt += f"視聴者からの新しいメッセージ: {prompt}\n\n応答:"
            
            # Ollama API呼び出し
            url = f"{self.base_url}/api/generate"
            data = {
                'model': self.model_name,
                'prompt': full_prompt,
                'stream': False,
                'options': {
                    'temperature': 0.8,
                    'max_tokens': 150,
                    'top_p': 0.9,
                    'frequency_penalty': 0.1,
                    'presence_penalty': 0.1
                }
            }
            
            response = requests.post(url, json=data, timeout=30)
            
            if response.status_code == 200:
                result = response.json()
                generated_text = result.get('response', '').strip()
                
                # 会話履歴に追加
                self._add_to_history(prompt, generated_text)
                
                return generated_text or "すみません、うまく応答できませんでした。"
            else:
                logger.error(f"Ollama API エラー: {response.status_code}")
                return "システムの調子が悪いようです。少し待ってからもう一度お試しください。"
            
        except requests.exceptions.Timeout:
            logger.error("LLM応答タイムアウト")
            return "考えるのに時間がかかりすぎました。すみません！"
        except Exception as e:
            logger.error(f"LLM応答生成エラー: {e}")
            return "申し訳ございませんが、応答を生成できませんでした。"
    
    def _add_to_history(self, user_input: str, ai_response: str):
        """会話履歴に追加"""
        self.conversation_history.append(f"ユーザー: {user_input} | AI: {ai_response}")
        
        # 履歴数制限
        if len(self.conversation_history) > self.max_history_length:
            self.conversation_history = self.conversation_history[-self.max_history_length:]
    
    def clear_history(self):
        """会話履歴をクリア"""
        self.conversation_history = []
        logger.info("会話履歴をクリアしました")
    
    def test_connection(self) -> bool:
        """Ollama接続テスト"""
        try:
            url = f"{self.base_url}/api/version"
            response = requests.get(url, timeout=10)
            return response.status_code == 200
        except:
            return False

class VoicevoxTTS:
    """VOICEVOX音声合成クラス（ネイティブ版）"""
    
    def __init__(self, voicevox_dir: str = "/opt/voicevox", speaker_id: int = 1):
        self.voicevox_dir = voicevox_dir
        self.speaker_id = speaker_id
        self.engine_process = None
        self.base_url = "http://localhost:50021"
        self.audio_cache = {}  # 音声キャッシュ
        self.max_cache_size = 100
        
    def start_engine(self) -> bool:
        """VOICEVOX Engine起動"""
        try:
            # エンジンが既に起動しているかチェック
            if self._is_engine_running():
                logger.info("VOICEVOX Engine already running")
                return True
            
            # Systemdサービスで起動を試行
            result = subprocess.run(['sudo', 'systemctl', 'start', 'voicevox'], 
                                 capture_output=True, text=True)
            
            if result.returncode == 0:
                # 起動待機
                for i in range(30):
                    if self._is_engine_running():
                        logger.info("VOICEVOX Engine started via systemd")
                        return True
                    time.sleep(1)
            
            # 直接起動を試行
            logger.info("Systemdでの起動に失敗。直接起動を試行...")
            return self._start_engine_directly()
            
        except Exception as e:
            logger.error(f"VOICEVOX Engine start error: {e}")
            return False
    
    def _start_engine_directly(self) -> bool:
        """VOICEVOX Engineを直接起動"""
        try:
            engine_path = os.path.join(self.voicevox_dir, "run")
            
            if not os.path.exists(engine_path):
                logger.error(f"VOICEVOX engine not found at {engine_path}")
                return False
                
            self.engine_process = subprocess.Popen(
                [engine_path, "--host", "127.0.0.1", "--port", "50021"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                cwd=self.voicevox_dir
            )
            
            # 起動待機
            for i in range(30):
                if self._is_engine_running():
                    logger.info("VOICEVOX Engine started directly")
                    return True
                time.sleep(1)
                
            logger.error("VOICEVOX Engine failed to start")
            return False
            
        except Exception as e:
            logger.error(f"Direct engine start error: {e}")
            return False
    
    def _is_engine_running(self) -> bool:
        """エンジンが動作中かチェック"""
        try:
            response = requests.get(f"{self.base_url}/version", timeout=3)
            return response.status_code == 200
        except:
            return False
    
    def stop_engine(self):
        """VOICEVOX Engine停止"""
        try:
            # Systemdサービス停止を試行
            subprocess.run(['sudo', 'systemctl', 'stop', 'voicevox'], 
                         capture_output=True)
            
            # 直接起動したプロセスがあれば停止
            if self.engine_process:
                self.engine_process.terminate()
                try:
                    self.engine_process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self.engine_process.kill()
                self.engine_process = None
                
        except Exception as e:
            logger.error(f"Engine stop error: {e}")
    
    def synthesize_speech(self, text: str, speaker_id: Optional[int] = None) -> bytes:
        """テキストを音声に変換"""
        if speaker_id is None:
            speaker_id = self.speaker_id
            
        # キャッシュチェック
        cache_key = f"{text}_{speaker_id}"
        if cache_key in self.audio_cache:
            logger.debug(f"音声キャッシュヒット: {text[:20]}...")
            return self.audio_cache[cache_key]
            
        try:
            # エンジンが停止している場合は再起動
            if not self._is_engine_running():
                logger.warning("VOICEVOX Engine not responding, restarting...")
                if not self.start_engine():
                    logger.error("Failed to restart VOICEVOX Engine")
                    return b""
            
            # テキストの前処理
            text = self._preprocess_text(text)
            
            # 音声クエリ生成
            query_url = f"{self.base_url}/audio_query"
            query_params = {'text': text, 'speaker': speaker_id}
            query_response = requests.post(query_url, params=query_params, timeout=15)
            
            if query_response.status_code != 200:
                logger.error(f"Audio query failed: {query_response.status_code} - {query_response.text}")
                return b""
                
            audio_query = query_response.json()
            
            # 音声合成パラメータ調整
            audio_query = self._adjust_audio_parameters(audio_query)
            
            # 音声合成
            synthesis_url = f"{self.base_url}/synthesis"
            synthesis_params = {'speaker': speaker_id}
            synthesis_response = requests.post(
                synthesis_url, 
                json=audio_query, 
                params=synthesis_params,
                timeout=30
            )
            
            if synthesis_response.status_code != 200:
                logger.error(f"Speech synthesis failed: {synthesis_response.status_code}")
                return b""
            
            audio_data = synthesis_response.content
            
            # キャッシュに保存
            self._add_to_cache(cache_key, audio_data)
            
            return audio_data
            
        except requests.exceptions.Timeout:
            logger.error("音声合成タイムアウト")
            return b""
        except Exception as e:
            logger.error(f"音声合成エラー: {e}")
            return b""
    
    def _preprocess_text(self, text: str) -> str:
        """テキストの前処理"""
        # 不要な文字の除去
        text = text.replace('\n', ' ').replace('\r', ' ')
        
        # 長すぎるテキストの切り詰め
        if len(text) > 200:
            text = text[:200] + "..."
            
        # 空白の正規化
        text = ' '.join(text.split())
        
        return text
    
    def _adjust_audio_parameters(self, audio_query: Dict) -> Dict:
        """音声パラメータの調整"""
        # 話速調整（少し速めに）
        audio_query['speedScale'] = 1.1
        
        # 音高調整（少し高めに）
        audio_query['pitchScale'] = 0.05
        
        # 抑揚調整
        audio_query['intonationScale'] = 1.2
        
        return audio_query
    
    def _add_to_cache(self, key: str, data: bytes):
        """音声キャッシュに追加"""
        if len(self.audio_cache) >= self.max_cache_size:
            # 最も古いエントリを削除
            oldest_key = next(iter(self.audio_cache))
            del self.audio_cache[oldest_key]
        
        self.audio_cache[key] = data
    
    def clear_cache(self):
        """音声キャッシュをクリア"""
        self.audio_cache.clear()
        logger.info("音声キャッシュをクリアしました")
    
    def get_available_speakers(self) -> List[Dict]:
        """利用可能なスピーカー一覧を取得"""
        try:
            response = requests.get(f"{self.base_url}/speakers", timeout=10)
            if response.status_code == 200:
                return response.json()
            return []
        except:
            return []

class RadioStreamingBot:
    """ラジオ配信ボットメインクラス"""
    
    def __init__(self, youtube_api_key: str, video_id: str, voicevox_dir: str = "/opt/voicevox"):
        self.comment_fetcher = YouTubeCommentFetcher(video_id, youtube_api_key)
        self.llm = OllamaLLM()
        self.tts = VoicevoxTTS(voicevox_dir)
        self.running = False
        self.stats = {
            'start_time': None,
            'comments_processed': 0,
            'superchats_received': 0,
            'audio_generated': 0,
            'errors_occurred': 0,
            'last_activity': None
        }
        
        # シグナルハンドラー設定
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
        
    def start(self) -> bool:
        """配信開始"""
        logger.info("24時間ラジオ配信ボット開始")
        
        # 依存サービスの確認
        if not self._check_dependencies():
            return False
        
        # VOICEVOX Engine起動
        logger.info("VOICEVOX Engine起動中...")
        if not self.tts.start_engine():
            logger.error("VOICEVOX Engine起動失敗")
            return False
        
        # コメント取得開始
        logger.info("YouTubeコメント取得開始...")
        if not self.comment_fetcher.start_fetching():
            logger.error("コメント取得開始失敗")
            return False
        
        # 統計情報初期化
        self.stats['start_time'] = datetime.now()
        self.stats['last_activity'] = time.time()
        
        self.running = True
        
        # 起動完了メッセージ
        self._speak_text("こんにちは！24時間AIラジオの配信を開始します。コメントお待ちしています！")
        
        # メインループ開始
        try:
            self._main_loop()
        except KeyboardInterrupt:
            logger.info("キーボード割り込みを受信")
        except Exception as e:
            logger.error(f"メインループエラー: {e}")
        finally:
            self.stop()
        
        return True
        
    def stop(self):
        """配信停止"""
        logger.info("ラジオ配信ボット停止中...")
        
        self.running = False
        
        # 終了メッセージ
        self._speak_text("配信を終了します。ご視聴ありがとうございました！")
        
        # サービス停止
        self.comment_fetcher.stop_fetching()
        self.tts.stop_engine()
        
        # 統計情報出力
        self._print_statistics()
        
        logger.info("ラジオ配信ボット停止完了")
    
    def _check_dependencies(self) -> bool:
        """依存サービスの確認"""
        # Ollama接続テスト
        if not self.llm.test_connection():
            logger.error("Ollamaに接続できません")
            return False
        
        # VOICEVOXディレクトリ確認
        if not os.path.exists(self.tts.voicevox_dir):
            logger.error(f"VOICEVOXディレクトリが見つかりません: {self.tts.voicevox_dir}")
            return False
        
        return True
        
    def _main_loop(self):
        """メインループ"""
        idle_messages = [
            "今日もいい一日ですね。何かお話ししませんか？",
            "音楽を聞きながら、のんびりとした時間を過ごしましょう。",
            "皆さんからのコメントやスーパーチャット、お待ちしています！",
            "何か気になることがあれば、お気軽にコメントしてくださいね。",
            "今日はどんな一日でしたか？お話聞かせてください。",
            "リラックスして、一緒に楽しい時間を過ごしましょう。"
        ]
        
        idle_counter = 0
        last_activity = time.time()
        last_stats_report = time.time()
        
        logger.info("メインループ開始")
        
        while self.running:
            try:
                # コメント処理
                comment = self.comment_fetcher.get_comment()
                
                if comment:
                    last_activity = time.time()
                    self.stats['last_activity'] = last_activity
                    self._process_comment(comment)
                    
                # 無反応時の自動発話（10分間隔）
                elif time.time() - last_activity > 600:
                    idle_message = idle_messages[idle_counter % len(idle_messages)]
                    self._speak_text(idle_message)
                    idle_counter += 1
                    last_activity = time.time()
                    self.stats['last_activity'] = last_activity
                
                # 統計情報の定期報告（1時間間隔）
                if time.time() - last_stats_report > 3600:
                    self._log_statistics()
                    last_stats_report = time.time()
                
                # CPU使用率軽減のための待機
                time.sleep(1)
                
            except KeyboardInterrupt:
                logger.info("配信停止指示を受信")
                break
            except Exception as e:
                logger.error(f"メインループエラー: {e}")
                self.stats['errors_occurred'] += 1
                time.sleep(5)  # エラー時は少し長めに待機
    
    def _process_comment(self, comment: Dict):
        """コメント処理"""
        try:
            author = comment['author']
            text = comment['text']
            is_superchat = comment['is_superchat']
            is_member = comment.get('is_member', False)
            is_moderator = comment.get('is_moderator', False)
            
            # 統計更新
            self.stats['comments_processed'] += 1
            if is_superchat:
                self.stats['superchats_received'] += 1
            
            # 応答内容の決定
            if is_superchat:
                amount = comment.get('superchat_amount', 0)
                currency = comment.get('superchat_currency', '')
                context = f"スーパーチャット {amount}{currency} を受け取りました"
                prompt = f"{author}さんからスーパーチャット「{text}」をいただきました。心からの感謝を込めて応答してください。"
            elif is_member:
                context = "チャンネルメンバーからのコメント"
                prompt = f"チャンネルメンバーの{author}さんからコメント「{text}」です。特別感を込めて応答してください。"
            elif is_moderator:
                context = "モデレーターからのコメント"
                prompt = f"モデレーターの{author}さんからコメント「{text}」です。"
            else:
                context = "通常のコメント"
                prompt = f"{author}さんからコメント「{text}」です。親しみやすく応答してください。"
            
            # LLMで応答生成
            logger.info(f"応答生成中: {author}さんのコメント")
            response = self.llm.generate_response(prompt, context)
            
            # 応答を音声で出力
            full_response = f"{author}さん、{response}"
            self._speak_text(full_response)
            
            logger.info(f"応答完了: {author}さん -> {response}")
            
        except Exception as e:
            logger.error(f"コメント処理エラー: {e}")
            self.stats['errors_occurred'] += 1
            # エラー時の代替応答
            self._speak_text(f"{comment.get('author', 'ゲスト')}さん、コメントありがとうございます！")
        
    def _speak_text(self, text: str):
        """テキストを音声で読み上げ"""
        try:
            logger.info(f"読み上げ開始: {text}")
            
            # VOICEVOX音声合成
            audio_data = self.tts.synthesize_speech(text)
            
            if audio_data:
                # 音声ファイル保存
                timestamp = int(time.time())
                audio_file = f"/tmp/speech_{timestamp}.wav"
                
                with open(audio_file, 'wb') as f:
                    f.write(audio_data)
                
                # 音声再生（OBSに音声入力）
                result = subprocess.run([
                    'ffplay', '-nodisp', '-autoexit', '-loglevel', 'quiet', audio_file
                ], capture_output=True)
                
                # 一時ファイル削除
                try:
                    os.remove(audio_file)
                except:
                    pass
                
                self.stats['audio_generated'] += 1
                logger.info("読み上げ完了")
                
            else:
                logger.error("音声合成に失敗しました")
                
        except Exception as e:
            logger.error(f"読み上げエラー: {e}")
            self.stats['errors_occurred'] += 1
    
    def _signal_handler(self, signum, frame):
        """シグナルハンドラー"""
        logger.info(f"シグナル {signum} を受信。停止処理を開始します。")
        self.running = False
    
    def _log_statistics(self):
        """統計情報をログ出力"""
        if self.stats['start_time']:
            uptime = datetime.now() - self.stats['start_time']
            logger.info(f"=== 配信統計 ===")
            logger.info(f"稼働時間: {uptime}")
            logger.info(f"処理コメント数: {self.stats['comments_processed']}")
            logger.info(f"受信スーパーチャット数: {self.stats['superchats_received']}")
            logger.info(f"生成音声数: {self.stats['audio_generated']}")
            logger.info(f"エラー発生数: {self.stats['errors_occurred']}")
            logger.info(f"待機中コメント数: {self.comment_fetcher.get_queue_size()}")
    
    def _print_statistics(self):
        """統計情報を表示"""
        print("\n" + "="*50)
        print("配信統計情報")
        print("="*50)
        
        if self.stats['start_time']:
            uptime = datetime.now() - self.stats['start_time']
            print(f"稼働時間: {uptime}")
        
        print(f"処理コメント数: {self.stats['comments_processed']}")
        print(f"受信スーパーチャット数: {self.stats['superchats_received']}")
        print(f"生成音声数: {self.stats['audio_generated']}")
        print(f"エラー発生数: {self.stats['errors_occurred']}")
        print("="*50)

def load_config():
    """設定ファイル読み込み"""
    config = {
        'YOUTUBE_API_KEY': os.getenv('YOUTUBE_API_KEY', 'YOUR_YOUTUBE_API_KEY'),
        'YOUTUBE_VIDEO_ID': os.getenv('YOUTUBE_VIDEO_ID', 'YOUR_LIVE_VIDEO_ID'),
        'VOICEVOX_DIR': os.getenv('VOICEVOX_DIR', '/opt/voicevox')
    }
    
    # config.envファイルがあれば読み込み
    if os.path.exists('config.env'):
        with open('config.env', 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip().strip('"').strip("'")
                    config[key] = value
    
    return config

def main():
    """メイン関数"""
    # ログディレクトリ作成
    os.makedirs('logs', exist_ok=True)
    
    # 設定読み込み
    config = load_config()
    
    # 必須設定の確認
    if config['YOUTUBE_API_KEY'] == 'YOUR_YOUTUBE_API_KEY':
        logger.error("YouTube API Keyが設定されていません。config.envを編集してください。")
        sys.exit(1)
    
    if config['YOUTUBE_VIDEO_ID'] == 'YOUR_LIVE_VIDEO_ID':
        logger.error("YouTube Video IDが設定されていません。config.envを編集してください。")
        sys.exit(1)
    
    # 配信ボット起動
    bot = RadioStreamingBot(
        config['YOUTUBE_API_KEY'], 
        config['YOUTUBE_VIDEO_ID'],
        config['VOICEVOX_DIR']
    )
    
    success = bot.start()
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
