# Win11Debloat / WinUtil の版に依存せず必ず入れるテレメトリ停止のベースライン。
# apply.ps1 が適用し、verify.ps1 が同じ定義で実機の状態を照合する (単一の正)。
#
# - Registry: 値はすべて DWord。HKCU は apply.ps1 を実行したユーザーに入る
# - Services: StartupType Disabled + 停止
# - Tasks:    無効化。その build に存在しないタスクは skip (verify でも absent 扱い)
# - Capabilities: Windows の追加機能 (Get-WindowsCapability) を削除。名前は ~~~~ より前で照合する
#
# Home / Pro では AllowTelemetry=0 は「必須 (1)」として扱われる。0 が効くのは
# Enterprise / Education のみ。送信本体の DiagTrack を止めるのが実効的な停止。
@{
    Registry = @(
        # 診断データ
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Value = 0 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'MaxTelemetryAllowed'; Value = 0 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowDeviceNameInTelemetry'; Value = 0 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'LimitDiagnosticLogCollection'; Value = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'DisableOneSettingsDownloads'; Value = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'DoNotShowFeedbackNotifications'; Value = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'; Name = 'AllowTelemetry'; Value = 0 }
        # 互換性テレメトリ (Application Experience / Inventory) と CEIP
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'AITEnable'; Value = 0 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'DisableInventory'; Value = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows'; Name = 'CEIPEnable'; Value = 0 }
        # エラー報告
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting'; Name = 'Disabled'; Value = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting'; Name = 'Disabled'; Value = 1 }
        # 診断データを使った「カスタマイズされたエクスペリエンス」/ 自動アプリ導入
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableTailoredExperiencesWithDiagnosticData'; Value = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsConsumerFeatures'; Value = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableSoftLanding'; Value = 1 }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy'; Name = 'TailoredExperiencesWithDiagnosticDataEnabled'; Value = 0 }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules'; Name = 'NumberOfSIUFInPeriod'; Value = 0 }
        # Copilot / Recall
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Value = 1 }
        @{ Path = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Value = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAIDataAnalysis'; Value = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'AllowRecallEnablement'; Value = 0 }
        @{ Path = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAIDataAnalysis'; Value = 1 }
        # 広告 ID
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo'; Name = 'DisabledByGroupPolicy'; Value = 1 }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Value = 0 }
        # 検索の Web 連携
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'AllowCortana'; Value = 0 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'DisableWebSearch'; Value = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'ConnectedSearchUseWeb'; Value = 0 }
        @{ Path = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer'; Name = 'DisableSearchBoxSuggestions'; Value = 1 }
        # アクティビティ履歴の送信。EnableActivityFeed は WinUtil の WPFTweaksActivity が
        # クリップボード履歴を残すために 1 にするので、ここでは宣言しない
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'PublishUserActivities'; Value = 0 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'UploadUserActivities'; Value = 0 }
        # Windows Backup UI (UWP 本体は CBS 管理で削除不可、機能だけ無効化)
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsBackup'; Name = 'DisableWindowsBackupUI'; Value = 1 }
    )

    Services = @(
        'DiagTrack'          # Connected User Experiences and Telemetry (送信本体)
        'dmwappushservice'   # WAP Push (テレメトリのルーティング)
        'WerSvc'             # Windows Error Reporting
    )

    # PcaPatchDbTask (互換性アシスタントの DB 更新、送信はしない) は入れない。
    # 無効にしても起動のたびに Windows が Ready に戻すので、verify が毎回 DRIFT になる。
    Tasks = @(
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp'
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater'
        '\Microsoft\Windows\Application Experience\StartupAppTask'
        '\Microsoft\Windows\Application Experience\MareBackup'
        '\Microsoft\Windows\Autochk\Proxy'
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'
        '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'
        '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'
        '\Microsoft\Windows\Feedback\Siuf\DmClient'
        '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
        '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
        '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReporting'
    )

    Capabilities = @(
        'VBSCRIPT'                        # 非推奨、マルウェアの常套手段
        'Browser.InternetExplorer'        # Edge の IE モード
        'App.StepsRecorder'               # 非推奨 (ステップ記録ツール)
        'Media.WindowsMediaPlayer'        # 旧 Windows Media Player
        'Microsoft.Windows.PowerShell.ISE' # PowerShell 7 + WezTerm で代替
        'MathRecognizer'                  # 数式入力パネル
        'Microsoft.Wallpapers.Extended'   # 追加の壁紙
        'Hello.Face'                      # Windows Hello 顔認証 (IR カメラ無しなら不要)
    )
}
