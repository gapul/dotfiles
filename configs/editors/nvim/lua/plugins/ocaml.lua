-- OCaml 開発用カスタム設定
-- fl_jikken (関数・論理型プログラミング実験) 向けに型推論作業を支援
--
-- 前提:
--   * opam switch に ocaml-lsp-server, ocamlformat, merlin が入っていること
--   * lazyvim.json の extras に "lazyvim.plugins.extras.lang.ocaml" を追加済み

return {
  -- (1) ocamllsp: 型推論結果を可視化する設定を盛る
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        ocamllsp = {
          -- opam の ocaml-lsp-server を直接使う (mason 経由を避けて opam switch と整合させる)
          mason = false,
          cmd = { "ocamllsp" },
          settings = {
            extendedHover = { enable = true },
            codelens = { enable = true },
            inlayHints = { enable = true },
            syntaxDocumentation = { enable = true },
          },
          -- inlay hints を起動時から有効化
          on_attach = function(client, bufnr)
            if client.server_capabilities.inlayHintProvider then
              vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
            end
          end,
        },
      },
    },
  },

  -- (2) mason 経由で ocaml-lsp を入れさせない
  -- opam と二重インストールになると古い方が優先されることがある
  {
    "williamboman/mason-lspconfig.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      -- ocamllsp は除外
      opts.ensure_installed = vim.tbl_filter(function(name)
        return name ~= "ocamllsp"
      end, opts.ensure_installed)
    end,
  },

  -- (3) ocamlformat: フォーマッタ
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        ocaml = { "ocamlformat" },
      },
    },
  },

  -- (4) vim-slime: utop / ocaml REPL に式を送信
  -- ;; をセル区切りにしてトップレベル定義を簡単に送れるようにする
  {
    "jpalardy/vim-slime",
    ft = { "ocaml" },
    init = function()
      vim.g.slime_target = "neovim"
      vim.g.slime_dont_ask_default = 1
      vim.g.slime_cell_delimiter = ";;"
      vim.g.slime_no_mappings = 1
    end,
    keys = {
      { "<leader>os", "<Plug>SlimeRegionSend", mode = "x", desc = "Send region to REPL" },
      { "<leader>os", "<Plug>SlimeMotionSend", mode = "n", desc = "Send motion to REPL" },
      { "<leader>oS", "<Plug>SlimeLineSend", mode = "n", desc = "Send line to REPL" },
      { "<leader>oc", "<Plug>SlimeCellSend", mode = "n", desc = "Send cell (;;-delimited) to REPL" },
    },
  },

  -- (5) utop を split で開くユーザコマンド
  -- :OcamlRepl で右側に utop を起動 (#use "topfind";; #require "fl-jikken-unifier";; を自動投入)
  {
    "LazyVim/LazyVim",
    keys = {
      {
        "<leader>or",
        function()
          vim.cmd("vsplit | terminal utop")
          vim.cmd("startinsert")
          local chan = vim.b.terminal_job_id
          if chan then
            vim.fn.chansend(chan, '#use "topfind";;\n#require "fl-jikken-unifier";;\n')
          end
        end,
        desc = "Open utop REPL (with fl-jikken-unifier loaded)",
      },
    },
  },

  -- (6) which-key: <leader>o を OCaml グループとして登録
  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        { "<leader>o", group = "ocaml" },
      },
    },
  },
}
