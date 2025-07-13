# QMK/VIAカスタムキーボード統合の高度化 - TODO

**ID**: todo-5  
**優先度**: 低  
**推定時間**: 5-6時間  
**ステータス**: 基本機能完了・高度化待ち

## 概要

現在QMK/VIA統合の基本機能は実装済みだが、AI最適化、プロファイル管理、自動化などの高度な機能の実装が必要。

## 現在の状況

### 完了済み機能
- ✅ QMK CLI環境構築
- ✅ VIA統合設定
- ✅ 基本的なキーマップ管理
- ✅ プリセットプロファイル（developer, writer, gamer）
- ✅ ヘルスチェック機能

### 未実装・高度化が必要な機能
- ❌ AI最適化によるキーマップ分析
- ❌ 使用パターン学習システム
- ❌ 自動プロファイル切り替え
- ❌ キーマップバージョン管理
- ❌ クラウド同期機能

## 実装目標

- **AI最適化**: 使用パターン分析による最適なキーマップ提案
- **学習システム**: キー使用頻度の自動分析と改善提案
- **自動化**: アプリケーション連動による自動プロファイル切り替え
- **バージョン管理**: キーマップの履歴管理とロールバック機能
- **クラウド統合**: 複数デバイス間でのキーマップ同期

## 実装手順

### Phase 1: AI最適化システム

#### 1. キー使用パターン分析
```bash
#!/usr/bin/env bash
# scripts/keymap-usage-analyzer.sh

# キーロガーの設定（プライバシー考慮）
setup_keylogging() {
    echo "🔑 Setting up keyboard usage analysis..."
    
    # macOS用のキーロガー（最小限のデータ収集）
    cat > "$HOME/.qmk/keylogger.py" << 'EOF'
#!/usr/bin/env python3
"""
プライバシー配慮型キーボード使用パターン分析
実際のキー内容は記録せず、使用頻度のみを統計
"""

import json
import time
from collections import defaultdict, Counter
from datetime import datetime
import threading
import pynput.keyboard as keyboard

class KeyboardAnalyzer:
    def __init__(self):
        self.key_counts = Counter()
        self.key_sequences = defaultdict(int)
        self.session_start = datetime.now()
        self.last_keys = []
        self.save_interval = 300  # 5分ごとに保存
        
    def on_key_press(self, key):
        try:
            # プライバシー配慮：実際のキー内容は記録しない
            key_name = self.get_key_category(key)
            self.key_counts[key_name] += 1
            
            # キーシーケンス分析（2キーの組み合わせのみ）
            if len(self.last_keys) >= 1:
                sequence = f"{self.last_keys[-1]}->{key_name}"
                self.key_sequences[sequence] += 1
            
            self.last_keys.append(key_name)
            if len(self.last_keys) > 5:
                self.last_keys.pop(0)
                
        except Exception as e:
            print(f"Error in key analysis: {e}")
    
    def get_key_category(self, key):
        """キーをカテゴリに分類（プライバシー保護）"""
        try:
            if hasattr(key, 'char') and key.char:
                if key.char.isalpha():
                    return 'alpha'
                elif key.char.isdigit():
                    return 'digit'
                elif key.char in '!@#$%^&*()_+-=[]{}|;:,.<>?':
                    return 'symbol'
                else:
                    return 'other'
            else:
                # 特殊キー
                key_str = str(key)
                if 'shift' in key_str.lower():
                    return 'shift'
                elif 'ctrl' in key_str.lower() or 'cmd' in key_str.lower():
                    return 'modifier'
                elif 'space' in key_str.lower():
                    return 'space'
                elif 'enter' in key_str.lower():
                    return 'enter'
                elif 'backspace' in key_str.lower():
                    return 'backspace'
                elif 'tab' in key_str.lower():
                    return 'tab'
                else:
                    return 'special'
        except:
            return 'unknown'
    
    def save_analysis(self):
        """分析結果を保存"""
        data = {
            'session_start': self.session_start.isoformat(),
            'analysis_time': datetime.now().isoformat(),
            'key_counts': dict(self.key_counts),
            'key_sequences': dict(self.key_sequences),
            'total_keys': sum(self.key_counts.values())
        }
        
        with open(f"{os.environ['HOME']}/.qmk/usage_data.json", 'w') as f:
            json.dump(data, f, indent=2)
    
    def start_analysis(self, duration_hours=1):
        """分析開始"""
        print(f"🔍 Starting keyboard analysis for {duration_hours} hours...")
        print("⚠️  Only usage patterns are recorded, not actual keystrokes")
        
        # 定期保存スレッド
        def save_periodically():
            while True:
                time.sleep(self.save_interval)
                self.save_analysis()
        
        save_thread = threading.Thread(target=save_periodically, daemon=True)
        save_thread.start()
        
        # キーボードリスナー開始
        with keyboard.Listener(on_press=self.on_key_press) as listener:
            time.sleep(duration_hours * 3600)
            listener.stop()
        
        self.save_analysis()
        print("✅ Analysis completed and saved")

if __name__ == "__main__":
    import os
    os.makedirs(f"{os.environ['HOME']}/.qmk", exist_ok=True)
    
    analyzer = KeyboardAnalyzer()
    analyzer.start_analysis()
EOF

    chmod +x "$HOME/.qmk/keylogger.py"
}

# AI分析による最適化提案
generate_optimization_suggestions() {
    echo "🤖 Generating AI-powered optimization suggestions..."
    
    # Ollama使用のキーマップ最適化
    local usage_data="$HOME/.qmk/usage_data.json"
    
    if [ ! -f "$usage_data" ]; then
        echo "❌ No usage data found. Run keymap analysis first."
        return 1
    fi
    
    # AI分析プロンプト
    local analysis_prompt="あなたはキーボード最適化の専門家です。以下のキーボード使用データを分析して、QMKキーマップの最適化提案を行ってください。

使用データ:
$(cat "$usage_data")

以下の観点で分析してください：
1. 最も使用頻度の高いキーの配置最適化
2. 効率的なレイヤー構成の提案
3. マクロ化すべきキーシーケンスの特定
4. エルゴノミクス改善の提案
5. 特定のワークフロー（開発、ライティング等）に最適化された配置

markdown形式で具体的な改善案を提示してください。"

    # Ollama経由でAI分析実行
    if command -v ollama &>/dev/null; then
        ollama run codellama "$analysis_prompt" > "$HOME/.qmk/ai_optimization_report.md"
        echo "✅ AI optimization report generated: ~/.qmk/ai_optimization_report.md"
    else
        echo "⚠️  Ollama not available. Manual analysis required."
    fi
}
```

#### 2. プロファイル学習システム
```nix
# nix/darwin/keyboard/ai-optimization.nix
{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    python3
    (python3.withPackages (ps: with ps; [
      pynput          # キーボード監視
      matplotlib      # データ可視化
      pandas          # データ分析
      numpy           # 数値計算
      scikit-learn    # 機械学習
    ]))
  ];

  # AI最適化スクリプト
  home.file.".qmk/ai-keymap-optimizer.py" = {
    executable = true;
    text = ''
      #!/usr/bin/env python3
      """
      QMK Keymap AI Optimizer
      
      使用パターンを学習して最適なキーマップを提案
      """
      
      import json
      import os
      from datetime import datetime, timedelta
      from collections import defaultdict
      import pandas as pd
      import numpy as np
      from sklearn.cluster import KMeans
      from sklearn.preprocessing import StandardScaler
      
      class KeymapOptimizer:
          def __init__(self):
              self.data_dir = os.path.expanduser("~/.qmk")
              self.usage_files = []
              self.load_usage_data()
          
          def load_usage_data(self):
              """過去の使用データを読み込み"""
              for file in os.listdir(self.data_dir):
                  if file.startswith("usage_") and file.endswith(".json"):
                      self.usage_files.append(os.path.join(self.data_dir, file))
          
          def analyze_patterns(self):
              """使用パターンを分析"""
              all_data = []
              
              for file in self.usage_files:
                  with open(file, 'r') as f:
                      data = json.load(f)
                      all_data.append(data)
              
              # パターン分析
              patterns = {
                  'hourly_usage': self.analyze_hourly_patterns(all_data),
                  'key_efficiency': self.analyze_key_efficiency(all_data),
                  'sequence_optimization': self.analyze_sequences(all_data),
                  'layer_usage': self.analyze_layer_usage(all_data)
              }
              
              return patterns
          
          def analyze_hourly_patterns(self, data):
              """時間帯別使用パターン分析"""
              hourly = defaultdict(lambda: defaultdict(int))
              
              for session in data:
                  hour = datetime.fromisoformat(session['session_start']).hour
                  for key, count in session['key_counts'].items():
                      hourly[hour][key] += count
              
              return dict(hourly)
          
          def analyze_key_efficiency(self, data):
              """キー効率分析"""
              total_counts = defaultdict(int)
              
              for session in data:
                  for key, count in session['key_counts'].items():
                      total_counts[key] += count
              
              # 効率スコア計算（使用頻度vs配置の便利さ）
              efficiency_scores = {}
              for key, count in total_counts.items():
                  # 基本的な効率スコア（実際のキーボードレイアウトに基づく）
                  base_score = self.get_key_accessibility_score(key)
                  efficiency_scores[key] = count / base_score if base_score > 0 else 0
              
              return efficiency_scores
          
          def get_key_accessibility_score(self, key_category):
              """キーカテゴリのアクセシビリティスコア"""
              accessibility = {
                  'alpha': 1.0,      # ホームポジション
                  'space': 0.8,      # 親指
                  'enter': 0.7,      # 小指
                  'backspace': 0.6,  # 小指上段
                  'shift': 0.5,      # 小指下段
                  'modifier': 0.4,   # 親指以外
                  'digit': 0.3,      # 上段
                  'symbol': 0.2,     # 特殊配置
                  'special': 0.1,    # ファンクションキー等
                  'tab': 0.3,
                  'other': 0.1,
                  'unknown': 0.1
              }
              return accessibility.get(key_category, 0.1)
          
          def generate_optimizations(self):
              """最適化提案を生成"""
              patterns = self.analyze_patterns()
              
              optimizations = {
                  'layout_suggestions': self.suggest_layout_changes(patterns),
                  'layer_optimizations': self.suggest_layer_changes(patterns),
                  'macro_opportunities': self.suggest_macros(patterns),
                  'ergonomic_improvements': self.suggest_ergonomics(patterns)
              }
              
              return optimizations
          
          def suggest_layout_changes(self, patterns):
              """レイアウト変更提案"""
              efficiency = patterns['key_efficiency']
              
              # 高頻度だが効率の悪いキーを特定
              inefficient_high_use = {}
              for key, score in efficiency.items():
                  if score > 100:  # 高使用頻度だが非効率
                      inefficient_high_use[key] = score
              
              suggestions = []
              for key in sorted(inefficient_high_use.keys(), 
                              key=lambda k: inefficient_high_use[k], reverse=True):
                  suggestions.append({
                      'key': key,
                      'current_efficiency': inefficient_high_use[key],
                      'suggestion': f'{key}キーをより便利な位置に移動を検討',
                      'priority': 'high' if inefficient_high_use[key] > 200 else 'medium'
                  })
              
              return suggestions
          
          def suggest_macros(self, patterns):
              """マクロ提案"""
              sequences = patterns.get('sequence_optimization', {})
              
              macro_candidates = []
              for seq, count in sequences.items():
                  if count > 50 and '->' in seq:  # 頻繁に使用されるシーケンス
                      macro_candidates.append({
                          'sequence': seq,
                          'frequency': count,
                          'suggestion': f'{seq}をマクロ化して効率向上',
                          'estimated_time_saved': count * 0.2  # 秒
                      })
              
              return sorted(macro_candidates, 
                          key=lambda x: x['estimated_time_saved'], reverse=True)
          
          def save_report(self, optimizations):
              """最適化レポートを保存"""
              report = {
                  'generated': datetime.now().isoformat(),
                  'optimizations': optimizations,
                  'summary': {
                      'total_suggestions': len(optimizations.get('layout_suggestions', [])),
                      'macro_opportunities': len(optimizations.get('macro_opportunities', [])),
                      'potential_time_saved': sum(m.get('estimated_time_saved', 0) 
                                                for m in optimizations.get('macro_opportunities', []))
                  }
              }
              
              with open(f"{self.data_dir}/optimization_report.json", 'w') as f:
                  json.dump(report, f, indent=2)
              
              # マークダウンレポート生成
              self.generate_markdown_report(report)
          
          def generate_markdown_report(self, report):
              """マークダウン形式のレポート生成"""
              md_content = f"""# QMK Keymap Optimization Report

Generated: {report['generated']}

## Summary

- Total optimization suggestions: {report['summary']['total_suggestions']}
- Macro opportunities: {report['summary']['macro_opportunities']}
- Potential time saved: {report['summary']['potential_time_saved']:.1f} seconds per day

## Layout Optimization Suggestions

"""
              
              for suggestion in report['optimizations'].get('layout_suggestions', []):
                  md_content += f"### {suggestion['key']} Key Optimization\n"
                  md_content += f"- **Priority**: {suggestion['priority']}\n"
                  md_content += f"- **Current Efficiency**: {suggestion['current_efficiency']:.1f}\n"
                  md_content += f"- **Suggestion**: {suggestion['suggestion']}\n\n"
              
              md_content += "## Macro Opportunities\n\n"
              
              for macro in report['optimizations'].get('macro_opportunities', []):
                  md_content += f"### {macro['sequence']}\n"
                  md_content += f"- **Frequency**: {macro['frequency']} times\n"
                  md_content += f"- **Time Saved**: {macro['estimated_time_saved']:.1f} seconds\n"
                  md_content += f"- **Suggestion**: {macro['suggestion']}\n\n"
              
              with open(f"{self.data_dir}/optimization_report.md", 'w') as f:
                  f.write(md_content)
      
      if __name__ == "__main__":
          optimizer = KeymapOptimizer()
          optimizations = optimizer.generate_optimizations()
          optimizer.save_report(optimizations)
          print("✅ Optimization report generated!")
          print(f"📄 Report saved to: ~/.qmk/optimization_report.md")
    '';
  };
}
```

### Phase 2: 自動プロファイル切り替え

#### 1. アプリケーション連動システム
```bash
#!/usr/bin/env bash
# scripts/auto-profile-switcher.sh

# アプリケーション検出とプロファイル自動切り替え
setup_auto_profile_switching() {
    echo "🔄 Setting up automatic profile switching..."
    
    # アプリケーション-プロファイルマッピング設定
    cat > "$HOME/.qmk/app-profile-mapping.json" << 'EOF'
{
  "application_profiles": {
    "Code": "developer",
    "Xcode": "developer", 
    "IntelliJ IDEA": "developer",
    "Neovim": "developer",
    "Terminal": "developer",
    "WezTerm": "developer",
    
    "Notion": "writer",
    "Obsidian": "writer",
    "Pages": "writer",
    "Microsoft Word": "writer",
    "Typora": "writer",
    
    "Steam": "gamer",
    "Epic Games Launcher": "gamer",
    "Minecraft": "gamer",
    "Among Us": "gamer",
    
    "Figma": "designer",
    "Adobe Photoshop": "designer",
    "Sketch": "designer"
  },
  "default_profile": "standard",
  "switch_delay": 2.0,
  "notification": true
}
EOF

    # macOS用アプリケーション監視スクリプト
    cat > "$HOME/.qmk/app-monitor.py" << 'EOF'
#!/usr/bin/env python3
"""
macOS Application Monitor for Automatic QMK Profile Switching
"""

import json
import time
import subprocess
import os
from datetime import datetime

class AppMonitor:
    def __init__(self):
        self.config_file = os.path.expanduser("~/.qmk/app-profile-mapping.json")
        self.load_config()
        self.current_profile = self.config.get("default_profile", "standard")
        self.last_app = None
        
    def load_config(self):
        """設定ファイル読み込み"""
        try:
            with open(self.config_file, 'r') as f:
                self.config = json.load(f)
        except FileNotFoundError:
            self.config = {
                "application_profiles": {},
                "default_profile": "standard",
                "switch_delay": 2.0,
                "notification": True
            }
    
    def get_active_app(self):
        """現在アクティブなアプリケーションを取得"""
        try:
            script = '''
            tell application "System Events"
                set frontApp to first application process whose frontmost is true
                set appName to name of frontApp
            end tell
            return appName
            '''
            result = subprocess.run(['osascript', '-e', script], 
                                  capture_output=True, text=True)
            return result.stdout.strip()
        except Exception as e:
            print(f"Error getting active app: {e}")
            return None
    
    def get_profile_for_app(self, app_name):
        """アプリケーションに対応するプロファイルを取得"""
        app_profiles = self.config.get("application_profiles", {})
        return app_profiles.get(app_name, self.config.get("default_profile", "standard"))
    
    def switch_profile(self, profile_name):
        """QMKプロファイルを切り替え"""
        try:
            # QMKプロファイル切り替えコマンド実行
            switch_command = f"qmk-keymap switch {profile_name}"
            result = subprocess.run(switch_command.split(), 
                                  capture_output=True, text=True)
            
            if result.returncode == 0:
                self.current_profile = profile_name
                self.log_profile_switch(profile_name)
                
                if self.config.get("notification", True):
                    self.send_notification(f"Switched to {profile_name} profile")
                
                return True
            else:
                print(f"Error switching profile: {result.stderr}")
                return False
                
        except Exception as e:
            print(f"Error in profile switching: {e}")
            return False
    
    def send_notification(self, message):
        """macOS通知を送信"""
        try:
            subprocess.run([
                'osascript', '-e', 
                f'display notification "{message}" with title "QMK Profile Switcher"'
            ])
        except:
            pass
    
    def log_profile_switch(self, profile_name):
        """プロファイル切り替えをログ"""
        log_file = os.path.expanduser("~/.qmk/profile_switches.log")
        with open(log_file, 'a') as f:
            f.write(f"{datetime.now().isoformat()} - Switched to {profile_name}\\n")
    
    def monitor_applications(self):
        """アプリケーション監視メインループ"""
        print("🔍 Starting application monitoring for auto profile switching...")
        print(f"Current profile: {self.current_profile}")
        
        while True:
            try:
                current_app = self.get_active_app()
                
                if current_app and current_app != self.last_app:
                    required_profile = self.get_profile_for_app(current_app)
                    
                    if required_profile != self.current_profile:
                        print(f"📱 App changed to: {current_app}")
                        print(f"🔄 Switching profile: {self.current_profile} → {required_profile}")
                        
                        # 切り替え遅延
                        time.sleep(self.config.get("switch_delay", 2.0))
                        
                        # プロファイル切り替え実行
                        if self.switch_profile(required_profile):
                            print(f"✅ Successfully switched to {required_profile} profile")
                        else:
                            print(f"❌ Failed to switch to {required_profile} profile")
                    
                    self.last_app = current_app
                
                time.sleep(1)  # 1秒間隔でチェック
                
            except KeyboardInterrupt:
                print("\\n🛑 Monitoring stopped by user")
                break
            except Exception as e:
                print(f"Error in monitoring: {e}")
                time.sleep(5)

if __name__ == "__main__":
    monitor = AppMonitor()
    monitor.monitor_applications()
EOF

    chmod +x "$HOME/.qmk/app-monitor.py"
    
    echo "✅ Auto profile switching configured"
    echo "💡 Run: python3 ~/.qmk/app-monitor.py to start monitoring"
}
```

### Phase 3: バージョン管理とクラウド同期

#### 1. キーマップバージョン管理
```bash
#!/usr/bin/env bash
# scripts/keymap-version-control.sh

# キーマップのGitベースバージョン管理
setup_keymap_versioning() {
    local keymap_repo="$HOME/.qmk/keymaps"
    
    echo "📦 Setting up keymap version control..."
    
    # キーマップ専用リポジトリ初期化
    if [ ! -d "$keymap_repo" ]; then
        mkdir -p "$keymap_repo"
        cd "$keymap_repo"
        git init
        
        # .gitignore設定
        cat > .gitignore << 'EOF'
# Compiled files
*.hex
*.bin
*.uf2

# OS files
.DS_Store
Thumbs.db

# Temporary files
*.tmp
*.swp
*~

# Logs
*.log
EOF
        
        # README作成
        cat > README.md << 'EOF'
# QMK Keymaps Repository

This repository contains versioned QMK keymaps for various keyboards and profiles.

## Structure

```
keyboards/
├── planck/
│   ├── developer/
│   ├── writer/
│   └── gamer/
├── corne/
└── lily58/

profiles/
├── base-developer.json
├── base-writer.json
└── base-gamer.json

backups/
└── [automatic backups]
```

## Usage

- `keymap-backup <keyboard> <profile>` - Create backup
- `keymap-restore <backup-id>` - Restore from backup
- `keymap-diff <version1> <version2>` - Compare versions
- `keymap-history <keyboard>` - View change history
EOF
        
        git add .
        git commit -m "Initial keymap repository setup"
        
        echo "✅ Keymap repository initialized at $keymap_repo"
    fi
}

# キーマップバックアップ
backup_keymap() {
    local keyboard="$1"
    local profile="$2"
    local keymap_repo="$HOME/.qmk/keymaps"
    
    if [ -z "$keyboard" ] || [ -z "$profile" ]; then
        echo "Usage: backup_keymap <keyboard> <profile>"
        return 1
    fi
    
    echo "💾 Backing up keymap: $keyboard/$profile"
    
    # バックアップディレクトリ作成
    local backup_dir="$keymap_repo/keyboards/$keyboard/$profile"
    mkdir -p "$backup_dir"
    
    # 現在のキーマップをコピー
    local qmk_dir="$HOME/qmk_firmware/keyboards/$keyboard/keymaps/$profile"
    if [ -d "$qmk_dir" ]; then
        cp -r "$qmk_dir"/* "$backup_dir/"
        
        # VIA設定も保存
        local via_config="$HOME/.config/via/keyboards/$keyboard-$profile.json"
        if [ -f "$via_config" ]; then
            cp "$via_config" "$backup_dir/via-config.json"
        fi
        
        # メタデータ作成
        cat > "$backup_dir/metadata.json" << EOF
{
    "keyboard": "$keyboard",
    "profile": "$profile",
    "backup_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "qmk_version": "$(qmk --version 2>/dev/null || echo 'unknown')",
    "via_config_included": $([ -f "$via_config" ] && echo "true" || echo "false")
}
EOF
        
        # Git コミット
        cd "$keymap_repo"
        git add .
        git commit -m "Backup $keyboard/$profile - $(date)"
        
        echo "✅ Keymap backed up successfully"
        
        # タグ作成（オプション）
        local tag="$keyboard-$profile-$(date +%Y%m%d-%H%M%S)"
        git tag "$tag"
        echo "🏷️  Tagged as: $tag"
        
    else
        echo "❌ Keymap directory not found: $qmk_dir"
        return 1
    fi
}
```

## 完了条件

### AI最適化システム
- [ ] キーボード使用パターンの自動分析が動作する
- [ ] AI による最適化提案が生成される
- [ ] プライバシーを考慮したデータ収集が実装されている
- [ ] 学習結果に基づく改善提案が提供される

### 自動プロファイル切り替え
- [ ] アプリケーション連動による自動切り替えが動作する
- [ ] カスタマイズ可能なアプリケーション-プロファイルマッピング
- [ ] 切り替え通知機能が実装されている
- [ ] 手動オーバーライド機能が利用可能

### バージョン管理・クラウド同期
- [ ] キーマップのGitベースバージョン管理が動作する
- [ ] 自動バックアップ機能が実装されている
- [ ] 差分比較・履歴確認機能が利用可能
- [ ] 復元・ロールバック機能が動作する

### 高度機能
- [ ] 使用統計の可視化ダッシュボード
- [ ] パフォーマンス改善の定量的測定
- [ ] 複数デバイス間でのキーマップ同期
- [ ] コミュニティキーマップ共有機能

## 関連ファイル

- `scripts/keymap-usage-analyzer.sh` - 使用パターン分析
- `scripts/auto-profile-switcher.sh` - 自動プロファイル切り替え
- `scripts/keymap-version-control.sh` - バージョン管理
- `nix/darwin/keyboard/ai-optimization.nix` - AI最適化設定
- `~/.qmk/` - QMK関連データディレクトリ

## 技術スタック

### AI・機械学習
- **Python**: データ分析・機械学習
- **scikit-learn**: パターン分析
- **pandas/numpy**: データ処理
- **Ollama**: LLM による提案生成

### 自動化
- **pynput**: キーボード監視
- **AppleScript**: macOS アプリケーション検出
- **systemd/launchd**: バックグラウンドサービス

### バージョン管理
- **Git**: キーマップ履歴管理
- **JSON**: 設定・メタデータ保存
- **シェルスクリプト**: 自動化タスク

## セキュリティ・プライバシー考慮

### データ収集の最小化
- 実際のキーストロークは記録しない
- キーカテゴリの統計のみ収集
- ローカルデータ保存（外部送信なし）

### ユーザー制御
- 分析機能のオプトアウト可能
- データ削除機能の提供
- 透明性のあるデータ利用

---

**作成日**: 2025年7月13日  
**最終更新**: 2025年7月13日  
**作成者**: Claude Code Assistant