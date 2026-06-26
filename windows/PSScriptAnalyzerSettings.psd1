@{
    # PSScriptAnalyzer ルール調整
    # - PSAvoidUsingWriteHost: 本リポの .ps1 は対話 UI 用に Write-Host で色を付ける
    #   (bootstrap の手順ログ、verify の OK/MISS 表示)。captured/redirect される
    #   想定が無いため許容。
    # - PSAvoidUsingInvokeExpression: starship init / zoxide init の出力 PowerShell
    #   コードを実行する公式パターン。回避手段が無い。
    # - PSUseApprovedVerbs: wsl-here / pbcopy 相当の関数を Mac/WSL の慣習名で公開
    #   するため。Approved verb (Get/Set/Enter 等) では UX が悪い。
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSAvoidUsingInvokeExpression',
        'PSUseApprovedVerbs'
    )
}
