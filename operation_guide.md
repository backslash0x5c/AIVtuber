# 24時間ラジオ配信システム 運用・メンテナンスガイド

## 🎯 運用概要

このシステムは24時間365日の連続運用を前提として設計されています。安定運用のためには、定期的な監視とメンテナンスが重要です。

### 運用方針
- **自動化優先**: 可能な限り自動化し、人的介入を最小限に
- **予防保全**: 問題が発生する前に対処
- **ログ重視**: 全ての動作をログに記録し、分析に活用
- **段階的対応**: 問題に応じて段階的にエスカレーション

## 📊 日常監視業務

### 毎日の監視項目（所要時間：5-10分）

#### 1. システム健康状態確認

```bash
# 基本健康チェック
./system_check.sh quick

# サービス状態確認
sudo systemctl status radio-streaming ollama voicevox

# リソース使用量確認
./startup.sh status
```

**正常な状態の例：**
```
✓ Ollama: 動作中
✓ VOICEVOX: 動作中  
✓ OBS Studio: 動作中
✓ メインアプリケーション: 動作中
メモリ使用率: 65%
CPU使用率: 25%
ディスク使用率: 45%
```

#### 2. 配信状態確認

- YouTube Studioで配信が継続されているか確認
- 視聴者数、コメント数の確認
- 音声品質の確認（サンプル視聴）

#### 3. ログ確認

```bash
# エラーログ確認（直近1時間）
grep -i "error\|critical\|fatal" logs/main_app.log | tail -20

# 配信統計確認
grep "処理コメント数\|音声生成数" logs/main_app.log | tail -5

# システムアラート確認
tail -20 logs/alerts.log
```

#### 4. パフォーマンス確認

```bash
# API応答時間確認
./system_check.sh perf

# プロセス監視
ps aux | grep -E "(radio_streaming|ollama|voicevox|obs)" | grep -v grep
```

### 毎週の監視項目（所要時間：20-30分）

#### 1. 詳細システム診断

```bash
# 完全診断実行
./system_check.sh full > weekly_check_$(date +%Y%m%d).log

# 結果確認
cat weekly_check_$(date +%Y%m%d).log | grep -E "(✓|✗|⚠)"
```

#### 2. ログ分析

```bash
# 週間エラー統計
cd logs/
for log in *.log; do
    echo "=== $log ==="
    grep -c "ERROR" "$log" 2>/dev/null || echo "0"
done

# 処理コメント数統計
grep "処理コメント数:" main_app.log | tail -7 | \
    awk '{sum+=$NF} END {print "週間コメント処理数:", sum}'
```

#### 3. 配信統計分析

- 週間視聴時間の確認
- コメント数の推移確認
- スーパーチャット統計
- 視聴者層の分析

#### 4. リソース使用傾向分析

```bash
# メモリ使用量の推移
grep "メモリ使用率" logs/startup.log | tail -168 | \  # 週間データ
    awk '{print $NF}' | sed 's/%//' | \
    awk '{sum+=$1; if($1>max) max=$1; if(min=="" || $1<min) min=$1} 
         END {print "平均:", sum/NR"% 最大:", max"% 最小:", min"%"}'
```

### 毎月の監視項目（所要時間：1-2時間）

#### 1. システム全体レビュー

- パフォーマンス傾向分析
- 障害発生状況のまとめ
- 改善点の洗い出し

#### 2. セキュリティ確認

```bash
# システム更新確認
sudo apt list --upgradable

# ログインアクセス確認
sudo grep "sudo" /var/log/auth.log | tail -50

# ファイル権限確認
find ~/radio-streaming -type f -name "*.log" -not -perm 640
find ~/radio-streaming -name "config.env" -not -perm 600
```

#### 3. バックアップ確認

```bash
# バックアップファイル確認
ls -la /backup/radio-streaming/ | tail -10

# バックアップ復元テスト（月1回）
mkdir -p /tmp/restore_test
cd /tmp/restore_test
tar -xzf /backup/radio-streaming/config_backup_latest.tar.gz
diff config.env ~/radio-streaming/config.env
```

## 🔧 定期メンテナンス

### 日次メンテナンス（自動実行）

システムの`maintenance.sh`により自動実行されます：

```bash
# 実行内容確認
cat maintenance.sh

# 手動実行（テスト用）
./maintenance.sh
```

**実行内容：**
- ログローテーション
- 一時ファイルクリーンアップ
- システムリソース記録
- 健康チェック実行

### 週次メンテナンス（手動実行）

```bash
# 1. システムパッケージ更新
sudo apt update
sudo apt list --upgradable

# 緊急でない更新適用
sudo apt upgrade -y

# 2. ログ分析・アーカイブ
cd logs/
mkdir -p archive/$(date +%Y%m)
gzip *.log.1 2>/dev/null || true
mv *.log.*.gz archive/$(date +%Y%m)/ 2>/dev/null || true

# 3. システム最適化
# メモリキャッシュクリア（必要時のみ）
# sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'

# 4. 設定ファイルバックアップ
cp config.env backup/config.env.$(date +%Y%m%d)
```

### 月次メンテナンス（計画停止）

**⚠️ 注意：このメンテナンスは配信を一時停止します**

```bash
# 1. システム停止
./startup.sh stop

# 2. システム更新
sudo apt update && sudo apt upgrade -y

# 3. Ollamaモデル更新確認
ollama list
# 新しいバージョンがあれば更新
# ollama pull gemma:1b

# 4. VOICEVOX更新確認
curl -s https://api.github.com/repos/VOICEVOX/voicevox_engine/releases/latest | \
    jq -r '.tag_name'

# 5. ディスク使用量最適化
sudo apt autoremove -y
sudo apt autoclean
docker system prune -f 2>/dev/null || true

# 6. ログファイル最適化
find logs/ -name "*.log" -size +50M -exec gzip {} \;
find logs/ -name "*.gz" -mtime +90 -delete

# 7. システム再起動（カーネル更新時）
if [ -f /var/run/reboot-required ]; then
    echo "再起動が必要です"
    sudo reboot
fi

# 8. システム復旧
./startup.sh start

# 9. 動作確認
./system_check.sh full
```

## 🚨 アラート・監視システム

### 自動アラート設定

#### システムアラート監視

```bash
# 監視デーモン起動
./monitor.sh daemon &

# 監視ログ確認
tail -f logs/alerts.log
```

#### アラート種類と対応

| アラート | 条件 | 対応レベル | 対応時間 |
|----------|------|-----------|----------|
| サービス停止 | メインサービス停止 | 🔴 緊急 | 即座 |
| API応答なし | 30秒以上無応答 | 🔴 緊急 | 5分以内 |
| メモリ不足 | 使用率90%以上 | 🟡 警告 | 30分以内 |
| ディスク不足 | 使用率90%以上 | 🟡 警告 | 1時間以内 |
| CPU高負荷 | 使用率90%以上持続 | 🟡 警告 | 30分以内 |

### 外部通知設定（オプション）

#### Discord/Slack通知

```bash
# Discord Webhook設定
echo 'DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/..."' >> config.env

# テスト通知
curl -X POST "$DISCORD_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d '{"content":"ラジオ配信システム動作テスト"}'
```

#### メール通知設定

```bash
# メール送信設定
sudo apt install -y mailutils

# テストメール
echo "システム動作テスト" | mail -s "ラジオ配信テスト" admin@example.com
```

## 🐛 トラブル対応手順

### レベル1: 軽微な問題（自動復旧対象）

#### コメント取得エラー
**症状：** YouTube APIエラー、一時的な接続エラー
**対応：** 自動再試行（システムが自動対応）

#### 音声合成一時エラー
**症状：** VOICEVOX API一時エラー
**対応：** 自動スキップ、エラーメッセージ読み上げ

### レベル2: 中程度の問題（手動対応必要）

#### メモリ不足
**症状：** システム動作が重い、応答遅延
**対応手順：**
```bash
# 1. メモリ使用量確認
free -h
ps aux --sort=-%mem | head -10

# 2. 不要プロセス終了
sudo pkill -f "不要なプロセス名"

# 3. システム再起動（重症時）
./startup.sh restart
```

#### ディスク容量不足
**症状：** ディスク使用率90%以上
**対応手順：**
```bash
# 1. 容量確認
df -h
du -sh logs/ backup/

# 2. ログファイル圧縮
cd logs/
gzip *.log.1 *.log.2 2>/dev/null || true

# 3. 古いファイル削除
find . -name "*.gz" -mtime +30 -delete
find /tmp -name "speech_*" -mtime +1 -delete
```

### レベル3: 重大な問題（緊急対応必要）

#### サービス完全停止
**症状：** メインアプリケーションが起動しない
**対応手順：**
```bash
# 1. 緊急停止
./startup.sh force-stop

# 2. ログ確認
tail -50 logs/main_app.log
sudo journalctl -u radio-streaming -n 50

# 3. 設定確認
./system_check.sh full

# 4. 段階的復旧
./startup.sh start

# 5. 復旧確認
./system_check.sh quick
```

#### YouTube配信停止
**症状：** OBS配信が停止、YouTube側でエラー
**対応手順：**
```bash
# 1. OBS状態確認
ps aux | grep obs

# 2. YouTube Studio確認
# ブラウザでYouTube Studioにアクセス
# ストリーム状態とエラーメッセージを確認

# 3. ストリームキー確認
grep "YOUTUBE_STREAM_KEY" config.env

# 4. OBS再起動
pkill -f obs
./start_obs.sh

# 5. 配信再開確認
```

#### データベース破損（該当する場合）
**症状：** 統計データが記録されない
**対応手順：**
```bash
# 1. データベースバックアップ
cp database.db database.db.backup.$(date +%Y%m%d_%H%M%S)

# 2. 整合性チェック
sqlite3 database.db "PRAGMA integrity_check;"

# 3. 修復試行
sqlite3 database.db "VACUUM;"

# 4. 最悪時はバックアップから復旧
cp backup/database.db.latest database.db
```

## 📈 パフォーマンス分析

### 定期パフォーマンス分析

#### 応答時間分析

```bash
# Ollama応答時間統計
grep "Ollama応答時間" logs/system_check.log | \
    awk '{print $NF}' | sed 's/秒//' | \
    awk '{sum+=$1; if($1>max) max=$1; if(min=="" || $1<min) min=$1} 
         END {print "平均:", sum/NR"s 最大:", max"s 最小:", min"s"}'

# VOICEVOX応答時間統計
grep "VOICEVOX応答時間" logs/system_check.log | \
    awk '{print $NF}' | sed 's/秒//' | \
    awk '{sum+=$1; if($1>max) max=$1; if(min=="" || $1<min) min=$1} 
         END {print "平均:", sum/NR"s 最大:", max"s 最小:", min"s"}'
```

#### リソース使用量傾向

```bash
# メモリ使用量推移グラフ（テキスト）
grep "メモリ使用率:" logs/startup.log | tail -24 | \
    awk '{print $NF}' | sed 's/%//' | \
    awk '{printf "%02d:00 ", NR; for(i=0;i<$1/2;i++) printf "█"; print " "$1"%"}'
```

### パフォーマンス最適化

#### メモリ最適化
```bash
# Python GCを強制実行
echo 'import gc; gc.collect()' | python3

# システムキャッシュ最適化
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
echo 'vm.vfs_cache_pressure=50' | sudo tee -a /etc/sysctl.conf
```

#### CPU最適化
```bash
# CPU親和性設定
echo 'CPU_AFFINITY="0,1"' >> config.env

# プロセス優先度調整
echo 'PROCESS_PRIORITY="-5"' >> config.env
```

## 📊 レポート作成

### 週次レポート生成

```bash
#!/bin/bash
# 週次レポート生成スクリプト

REPORT_FILE="weekly_report_$(date +%Y%m%d).md"

cat > "$REPORT_FILE" << EOF
# 週次運用レポート $(date +%Y年%m月%d日)

## システム稼働状況
- 稼働率: $(uptime | awk '{print $3,$4}' | sed 's/,//')
- 再起動回数: $(grep "システム起動" logs/startup.log | wc -l)

## エラー・警告統計
$(for log in logs/*.log; do
    echo "- $(basename $log): ERROR $(grep -c ERROR $log 2>/dev/null || echo 0)件, WARNING $(grep -c WARNING $log 2>/dev/null || echo 0)件"
done)

## パフォーマンス統計
- 平均メモリ使用率: $(grep "メモリ使用率" logs/startup.log | tail -7 | awk -F: '{sum+=$2} END {printf "%.1f%%", sum/7}')
- 平均CPU使用率: $(grep "CPU使用率" logs/startup.log | tail -7 | awk -F: '{sum+=$2} END {printf "%.1f%%", sum/7}')

## 配信統計
- 処理コメント数: $(grep "処理コメント数" logs/main_app.log | tail -1 | awk '{print $NF}')
- 音声生成数: $(grep "音声生成数" logs/main_app.log | tail -1 | awk '{print $NF}')

## 推奨アクション
$(if [ $(grep -c ERROR logs/*.log 2>/dev/null) -gt 10 ]; then
    echo "- エラー数が多いため、詳細調査が必要"
fi)
$(if [ $(df / | tail -1 | awk '{print $5}' | sed 's/%//') -gt 80 ]; then
    echo "- ディスク容量に注意が必要"
fi)

EOF

echo "週次レポート生成完了: $REPORT_FILE"
```

### 月次レポート生成

```bash
#!/bin/bash
# 月次レポート生成スクリプト

MONTH=$(date +%Y%m)
REPORT_FILE="monthly_report_$MONTH.json"

cat > "$REPORT_FILE" << EOF
{
  "period": "$MONTH",
  "generated": "$(date -Iseconds)",
  "uptime": {
    "total_hours": $(awk '{print $1/3600}' /proc/uptime),
    "service_restarts": $(grep -c "システム起動" logs/startup.log)
  },
  "performance": {
    "avg_memory_usage": $(grep "メモリ使用率" logs/startup.log | awk -F: '{sum+=$2; count++} END {printf "%.1f", sum/count}'),
    "avg_cpu_usage": $(grep "CPU使用率" logs/startup.log | awk -F: '{sum+=$2; count++} END {printf "%.1f", sum/count}'),
    "max_response_time": {
      "ollama": $(grep "Ollama応答時間" logs/system_check.log | awk '{print $NF}' | sed 's/秒//' | sort -n | tail -1),
      "voicevox": $(grep "VOICEVOX応答時間" logs/system_check.log | awk '{print $NF}' | sed 's/秒//' | sort -n | tail -1)
    }
  },
  "errors": {
    "total": $(grep -c ERROR logs/*.log 2>/dev/null || echo 0),
    "critical": $(grep -c CRITICAL logs/*.log 2>/dev/null || echo 0)
  },
  "recommendations": [
    $([ $(grep -c ERROR logs/*.log 2>/dev/null) -gt 50 ] && echo '"エラー数が多いため調査必要",')
    $([ $(df / | tail -1 | awk '{print $5}' | sed 's/%//') -gt 85 ] && echo '"ディスク容量拡張検討",')
    "定期メンテナンス継続"
  ]
}
EOF

echo "月次レポート生成完了: $REPORT_FILE"
```

## 🎯 運用品質向上

### 継続改善プロセス

1. **週次レビュー**
   - パフォーマンス指標の確認
   - エラー傾向の分析
   - 改善点の特定

2. **月次評価**
   - 稼働率の評価
   - コスト効率の確認
   - 技術的負債の識別

3. **四半期最適化**
   - システム構成の見直し
   - 新技術導入の検討
   - 運用プロセスの改善

### KPI（重要業績評価指標）

| 指標 | 目標値 | 測定方法 |
|------|--------|----------|
| システム稼働率 | 99.5%以上 | uptime計測 |
| 平均応答時間 | 3秒以下 | API応答時間 |
| エラー発生率 | 1%以下 | ログ分析 |
| メモリ使用率 | 80%以下 | リソース監視 |
| ディスク使用率 | 85%以下 | ディスク監視 |

---

この運用ガイドに従って定期的なメンテナンスと監視を行うことで、24時間安定したラジオ配信システムを維持できます。
