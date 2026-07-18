-- 打鍵ログの収集だけ利用する（AI提案/Bun CLI 部分は使わない）。
-- 貯まった ~/.local/share/nvim/ai_keymap/keystrokes.jsonl を
-- あとで Claude Code に読ませて解析する運用。
return {
  "ryoppippi/nvim-in-the-loop",
  event = "VeryLazy",
  main = "ai_keymap",
  opts = {
    start_immediately = true, -- 起動と同時にログ開始
    -- log_path はデフォルト (stdpath("data")/ai_keymap/keystrokes.jsonl) のまま
  },
}
