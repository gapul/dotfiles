-- Prolog (SWI-Prolog) 開発設定
-- fl_jikken 第10-12回 (論理型プログラミング)
--
-- 前提:
--   * swi-prolog がインストール済 (brew install swi-prolog)
--   * swipl コマンドが PATH にある
--   * LSP/整形は SWI パック lsp_server を使用:
--       swipl -g "pack_install(lsp_server,[interactive(false)])" -t halt

return {
  -- (1) Treesitter で .pl のシンタックスハイライト
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "prolog" })
    end,
  },

  -- (2) .pl を Prolog として認識(LazyVim/標準だと perl と曖昧) +
  --     Prolog バッファ限定の実行キーマップ / コマンドを登録
  --       <leader>rp : 現バッファを swipl で実行
  --       :SwiplLoad : REPL に現ファイルを load
  --     ※ グローバルではなく FileType=prolog のバッファローカルにして、
  --        他ファイルタイプで <leader>rp が暴発しないようにする
  {
    "LazyVim/LazyVim",
    init = function()
      vim.filetype.add({
        extension = {
          pl = "prolog",
          plt = "prolog",
          pro = "prolog",
        },
      })

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "prolog",
        callback = function(ev)
          local buf = ev.buf

          -- 保存時オートフォーマットを prolog では無効化する。
          -- lsp_server の整形はファイルを構文解析し直して「完全にパースできた節」
          -- だけを書き戻すため、編集途中(構文が一時的に不完全)なバッファを保存すると
          -- 書きかけの節が丸ごと消える破壊的挙動になる。
          -- 整形はコード完成後に手動 <leader>cf で行う運用にする。
          vim.b[buf].autoformat = false

          vim.keymap.set("n", "<leader>rp", function()
            vim.cmd("write")
            vim.cmd("vsplit | terminal swipl " .. vim.fn.expand("%"))
          end, { buffer = buf, desc = "Run current Prolog file in swipl" })

          vim.api.nvim_buf_create_user_command(buf, "SwiplLoad", function()
            vim.cmd("write")
            vim.cmd(string.format("vsplit | terminal swipl -s %s", vim.fn.expand("%")))
          end, { desc = "Open SWI-Prolog REPL and load current file" })
        end,
      })
    end,
  },

  -- (3) which-key に <leader>r グループ名を登録 (Space→r 押下時の見出し)
  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        { "<leader>r", group = "run", mode = "n" },
      },
    },
  },

  -- (4) LSP: prolog_ls (SWI パック lsp_server)
  --   診断 / ホバー / 定義ジャンプ / 参照 / 整形(textDocument/formatting) を提供
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        prolog_ls = {
          -- Mason ではなく swipl パックの実体を使う
          mason = false,
          -- 既定は root_markers = { "pack.pl" } だが、課題リポジトリには
          -- pack.pl が無いため .git もルート目印に加えて起動させる
          root_markers = { "pack.pl", ".git" },
        },
      },
    },
  },

  -- (5) mason 経由で prolog_ls を入れさせない (swipl パックと二重化させない)
  {
    "mason-org/mason-lspconfig.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      opts.ensure_installed = vim.tbl_filter(function(name)
        return name ~= "prolog_ls"
      end, opts.ensure_installed)
    end,
  },

  -- 整形について:
  --   conform の prolog builtin (swipl formatter) は in-place 書き換え型で
  --   stdout に結果を出さず、そのまま繋ぐとバッファを空にする危険がある。
  --   よって conform には登録せず、整形は LSP 経由 (<leader>cf) に任せる。
}
