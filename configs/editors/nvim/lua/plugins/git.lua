-- Git Integration Configuration
return {
  -- Git signs
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      require("gitsigns").setup({
        signs = {
          add = { text = "+" },
          change = { text = "~" },
          delete = { text = "_" },
          topdelete = { text = "‾" },
          changedelete = { text = "~" },
          untracked = { text = "┆" },
        },
        signcolumn = true,
        numhl = false,
        linehl = false,
        word_diff = false,
        watch_gitdir = {
          follow_files = true,
        },
        attach_to_untracked = true,
        current_line_blame = false,
        current_line_blame_opts = {
          virt_text = true,
          virt_text_pos = "eol",
          delay = 1000,
          ignore_whitespace = false,
        },
        current_line_blame_formatter = "<author>, <author_time:%Y-%m-%d> - <summary>",
        sign_priority = 6,
        update_debounce = 100,
        status_formatter = nil,
        max_file_length = 40000,
        preview_config = {
          border = "single",
          style = "minimal",
          relative = "cursor",
          row = 0,
          col = 1,
        },
        yadm = {
          enable = false,
        },
        on_attach = function(bufnr)
          local gs = package.loaded.gitsigns

          local function map(mode, l, r, opts)
            opts = opts or {}
            opts.buffer = bufnr
            vim.keymap.set(mode, l, r, opts)
          end

          -- Navigation
          map("n", "]c", function()
            if vim.wo.diff then
              return "]c"
            end
            vim.schedule(function()
              gs.next_hunk()
            end)
            return "<Ignore>"
          end, { expr = true, desc = "Next git hunk" })

          map("n", "[c", function()
            if vim.wo.diff then
              return "[c"
            end
            vim.schedule(function()
              gs.prev_hunk()
            end)
            return "<Ignore>"
          end, { expr = true, desc = "Previous git hunk" })

          -- Actions
          map("n", "<leader>hs", gs.stage_hunk, { desc = "Stage hunk" })
          map("n", "<leader>hr", gs.reset_hunk, { desc = "Reset hunk" })
          map("v", "<leader>hs", function()
            gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
          end, { desc = "Stage hunk" })
          map("v", "<leader>hr", function()
            gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
          end, { desc = "Reset hunk" })
          map("n", "<leader>hS", gs.stage_buffer, { desc = "Stage buffer" })
          map("n", "<leader>hu", gs.undo_stage_hunk, { desc = "Undo stage hunk" })
          map("n", "<leader>hR", gs.reset_buffer, { desc = "Reset buffer" })
          map("n", "<leader>hp", gs.preview_hunk, { desc = "Preview hunk" })
          map("n", "<leader>hb", function()
            gs.blame_line({ full = true })
          end, { desc = "Blame line" })
          map("n", "<leader>tb", gs.toggle_current_line_blame, { desc = "Toggle current line blame" })
          map("n", "<leader>hd", gs.diffthis, { desc = "Diff this" })
          map("n", "<leader>hD", function()
            gs.diffthis("~")
          end, { desc = "Diff this ~" })
          map("n", "<leader>td", gs.toggle_deleted, { desc = "Toggle deleted" })

          -- Text object
          map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", { desc = "Select hunk" })
        end,
      })
    end,
  },

  -- Git fugitive
  {
    "tpope/vim-fugitive",
    cmd = {
      "Git",
      "Gdiffsplit",
      "Gread",
      "Gwrite",
      "Ggrep",
      "GMove",
      "GDelete",
      "GBrowse",
      "GRemove",
      "GRename",
      "Glgrep",
      "Gedit",
    },
    ft = { "fugitive" },
    keys = {
      { "<leader>gs", "<cmd>Git<CR>", desc = "Git status" },
      { "<leader>gd", "<cmd>Gdiffsplit<CR>", desc = "Git diff split" },
      { "<leader>gc", "<cmd>Git commit<CR>", desc = "Git commit" },
      { "<leader>gb", "<cmd>Git blame<CR>", desc = "Git blame" },
      { "<leader>gl", "<cmd>Git log<CR>", desc = "Git log" },
      { "<leader>gp", "<cmd>Git push<CR>", desc = "Git push" },
      { "<leader>gP", "<cmd>Git pull<CR>", desc = "Git pull" },
    },
  },

  -- Enhanced Lazygit integration
  {
    "kdheepak/lazygit.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
    },
    keys = {
      { "<leader>gg", "<cmd>LazyGit<CR>", desc = "LazyGit" },
      { "<leader>gf", "<cmd>LazyGitFilter<CR>", desc = "LazyGit Filter" },
      { "<leader>gF", "<cmd>LazyGitFilterCurrentFile<CR>", desc = "LazyGit Filter Current File" },
      { "<leader>gc", "<cmd>LazyGitConfig<CR>", desc = "LazyGit Config" },
      { "<leader>gR", function() require('lazygit_utils').review_current_file() end, desc = "AI Review Current File" },
      { "<leader>gA", function() require('lazygit_utils').ai_commit_message() end, desc = "AI Commit Message" },
      { "<leader>gH", function() require('lazygit_utils').git_history_current_file() end, desc = "Git History Current File" },
      { "<leader>gC", function() require('lazygit_utils').git_checkout_branch() end, desc = "Checkout Branch (FZF)" },
    },
    cmd = {
      "LazyGit",
      "LazyGitConfig",
      "LazyGitFilter",
      "LazyGitFilterCurrentFile",
    },
    config = function()
      -- Enhanced LazyGit configuration
      vim.g.lazygit_floating_window_winblend = 5  -- slight transparency
      vim.g.lazygit_floating_window_scaling_factor = 0.95 -- larger window
      vim.g.lazygit_floating_window_corner_chars = { '╭', '╮', '╰', '╯' }
      vim.g.lazygit_floating_window_use_plenary = 1 -- use plenary for better window management
      vim.g.lazygit_use_neovim_remote = 1
      vim.g.lazygit_use_custom_config_file_path = 0
      
      -- Set up LazyGit configuration directory
      local config_dir = vim.fn.stdpath('config') .. '/lazygit'
      if vim.fn.isdirectory(config_dir) == 0 then
        vim.fn.mkdir(config_dir, 'p')
      end
      
      -- LazyGit config file content
      local lazygit_config = [[
gui:
  theme:
    lightTheme: false
    activeBorderColor:
      - '#f38ba8'
      - bold
    inactiveBorderColor:
      - '#6c7086'
    optionsTextColor:
      - '#89b4fa'
    selectedLineBgColor:
      - '#313244'
    selectedRangeBgColor:
      - '#313244'
    cherryPickedCommitBgColor:
      - '#45475a'
    cherryPickedCommitFgColor:
      - '#f38ba8'
    unstagedChangesColor:
      - '#f38ba8'
    defaultFgColor:
      - '#cdd6f4'
  commitLength:
    show: true
  mouseEvents: true
  skipDiscardChangeWarning: false
  skipStashWarning: false
  showFileTree: true
  showListFooter: true
  showRandomTip: false
  showBranchCommitHash: false
  showBottomLine: true
  showCommandLog: false
  commandLogSize: 8
  splitDiff: 'auto'
  skipRewordInEditorWarning: false
  windowSize: 'normal'
  border: 'rounded'
git:
  paging:
    colorArg: always
    pager: delta --dark --paging=never
  commit:
    signOff: false
    verbose: default
  merging:
    manualCommit: false
    args: ''
  log:
    order: 'topo-order'
    showGraph: 'when-maximised'
    showWholeGraph: false
  skipHookPrefix: WIP
  autoFetch: true
  autoRefresh: true
  branchLogCmd: 'git log --graph --color=always --abbrev-commit --decorate --date=relative --pretty=medium {{branchName}} --'
  allBranchesLogCmd: 'git log --graph --all --color=always --abbrev-commit --decorate --date=relative --pretty=medium'
  overrideGpg: false
  disableForcePushing: false
  parseEmoji: false
  diffContextSize: 3
update:
  method: prompt
  days: 14
refresher:
  refreshInterval: 10
  fetchInterval: 60
confirmOnQuit: false
quitOnTopLevelReturn: false
disableStartupPopups: false
notARepository: 'prompt'
promptToReturnFromSubprocess: true
keybinding:
  universal:
    quit: 'q'
    quit-alt1: '<c-c>'
    return: '<esc>'
    quitWithoutChangingDirectory: 'Q'
    togglePanel: '<tab>'
    prevItem: '<up>'
    nextItem: '<down>'
    prevItem-alt: 'k'
    nextItem-alt: 'j'
    prevPage: ','
    nextPage: '.'
    gotoTop: '<'
    gotoBottom: '>'
    prevBlock: '<left>'
    nextBlock: '<right>'
    prevBlock-alt: 'h'
    nextBlock-alt: 'l'
    jumpToBlock: ['1', '2', '3', '4', '5']
    nextMatch: 'n'
    prevMatch: 'N'
    optionMenu: 'x'
    optionMenu-alt1: '?'
    select: '<space>'
    goInto: '<enter>'
    openRecentRepos: '<c-r>'
    confirm: '<enter>'
    remove: 'd'
    new: 'n'
    edit: 'e'
    openFile: 'o'
    scrollUpMain: '<pgup>'
    scrollDownMain: '<pgdown>'
    scrollUpMain-alt1: 'K'
    scrollDownMain-alt1: 'J'
    scrollUpMain-alt2: '<c-u>'
    scrollDownMain-alt2: '<c-d>'
    executeCustomCommand: ':'
    createRebaseOptionsMenu: 'm'
    pushFiles: 'P'
    pullFiles: 'p'
    refresh: 'R'
    createPatchOptionsMenu: '<c-p>'
    nextTab: ']'
    prevTab: '['
    nextScreenMode: '+'
    prevScreenMode: '_'
    undo: 'z'
    redo: '<c-z>'
    filteringMenu: '<c-s>'
    diffingMenu: 'W'
    diffingMenu-alt: '<c-e>'
    copyToClipboard: '<c-o>'
    submitEditorText: '<enter>'
    appendNewline: '<a-enter>'
    extrasMenu: '@'
    toggleWhitespaceInDiffView: '<c-w>'
    increaseContextInDiffView: '}'
    decreaseContextInDiffView: '{'
  status:
    checkForUpdate: 'u'
    recentRepos: '<enter>'
  files:
    commitChanges: 'c'
    commitChangesWithoutHook: 'w'
    amendLastCommit: 'A'
    commitChangesWithEditor: 'C'
    ignoreFile: 'i'
    refreshFiles: 'r'
    stashAllChanges: 's'
    viewStashOptions: 'S'
    toggleStagedAll: 'a'
    viewResetOptions: 'D'
    fetch: 'f'
    toggleTreeView: '`'
    openMergeTool: 'M'
    openStatusFilter: '<c-b>'
  branches:
    createPullRequest: 'o'
    viewPullRequestOptions: 'O'
    copyPullRequestURL: '<c-y>'
    checkoutBranchByName: 'c'
    forceCheckoutBranch: 'F'
    rebaseBranch: 'r'
    renameBranch: 'R'
    mergeIntoCurrentBranch: 'M'
    viewGitFlowOptions: 'i'
    fastForward: 'f'
    createTag: 'T'
    pushTag: 'P'
    setUpstream: 'u'
    fetchRemote: 'f'
  commits:
    squashDown: 's'
    renameCommit: 'r'
    renameCommitWithEditor: 'R'
    viewResetOptions: 'g'
    markCommitAsFixup: 'f'
    createFixupCommit: 'F'
    squashAboveCommits: 'S'
    moveDownCommit: '<c-j>'
    moveUpCommit: '<c-k>'
    amendToCommit: 'A'
    pickCommit: 'p'
    revertCommit: 't'
    cherryPickCopy: 'c'
    cherryPickCopyRange: 'C'
    pasteCommits: 'v'
    tagCommit: 'T'
    checkoutCommit: '<space>'
    resetCherryPick: '<c-R>'
    copyCommitMessageToClipboard: '<c-y>'
    openLogMenu: '<c-l>'
    viewBisectOptions: 'b'
  stash:
    popStash: 'g'
    renameStash: 'r'
  commitFiles:
    checkoutCommitFile: 'c'
  main:
    toggleDragSelect: 'v'
    toggleDragSelect-alt: 'V'
    toggleSelectHunk: 'a'
    pickBothHunks: 'b'
  submodules:
    init: 'i'
    update: 'u'
    bulkMenu: 'b'
]]
      
      -- Write LazyGit config file
      local config_file = config_dir .. '/config.yml'
      local file = io.open(config_file, 'w')
      if file then
        file:write(lazygit_config)
        file:close()
        vim.g.lazygit_config_file_path = config_file
        vim.g.lazygit_use_custom_config_file_path = 1
      end
      
      -- Custom LazyGit commands
      vim.api.nvim_create_user_command('LazyGitConfig', function()
        vim.cmd('edit ' .. config_file)
      end, { desc = 'Edit LazyGit configuration' })
      
      -- Enhanced autocommands for better integration
      local lazygit_group = vim.api.nvim_create_augroup('LazyGitIntegration', { clear = true })
      
      -- Auto-refresh GitSigns after LazyGit operations
      vim.api.nvim_create_autocmd('User', {
        pattern = 'LazyGitExit',
        group = lazygit_group,
        callback = function()
          -- Refresh GitSigns
          if package.loaded.gitsigns then
            require('gitsigns').refresh()
          end
          
          -- Refresh file tree if available
          if package.loaded['nvim-tree'] then
            require('nvim-tree.api').tree.reload()
          end
          
          -- Refresh any open buffers to pick up changes
          vim.cmd('checktime')
        end,
      })
    end,
  },

  -- GitHub integration
  {
    "pwntester/octo.nvim",
    cmd = "Octo",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      require("octo").setup({
        default_remote = { "upstream", "origin" },
        reaction_viewer_hint_icon = "",
        user_icon = " ",
        timeline_marker = "",
        timeline_indent = "2",
        right_bubble_delimiter = "",
        left_bubble_delimiter = "",
        github_hostname = "",
        snippet_context_lines = 4,
        gh_env = {},
        timeout = 5000,
        ui = {
          use_signcolumn = true,
          use_signstatus = true,
        },
        issues = {
          order_by = {
            field = "CREATED_AT",
            direction = "DESC",
          },
        },
        pull_requests = {
          order_by = {
            field = "CREATED_AT",
            direction = "DESC",
          },
          always_select_remote_on_create = false,
        },
        file_panel = {
          size = 10,
          use_icons = true,
        },
        mappings = {
          issue = {
            close_issue = { lhs = "<space>ic", desc = "close issue" },
            reopen_issue = { lhs = "<space>io", desc = "reopen issue" },
            list_issues = { lhs = "<space>il", desc = "list open issues on same repo" },
            reload = { lhs = "<C-r>", desc = "reload issue" },
            open_in_browser = { lhs = "<C-b>", desc = "open issue in browser" },
            copy_url = { lhs = "<C-y>", desc = "copy url to system clipboard" },
            add_assignee = { lhs = "<space>aa", desc = "add assignee" },
            remove_assignee = { lhs = "<space>ad", desc = "remove assignee" },
            create_label = { lhs = "<space>lc", desc = "create label" },
            add_label = { lhs = "<space>la", desc = "add label" },
            remove_label = { lhs = "<space>ld", desc = "remove label" },
            goto_issue = { lhs = "<space>gi", desc = "navigate to a local repo issue" },
            add_comment = { lhs = "<space>ca", desc = "add comment" },
            delete_comment = { lhs = "<space>cd", desc = "delete comment" },
            next_comment = { lhs = "]c", desc = "go to next comment" },
            prev_comment = { lhs = "[c", desc = "go to previous comment" },
            react_hooray = { lhs = "<space>rp", desc = "add/remove 🎉 reaction" },
            react_heart = { lhs = "<space>rh", desc = "add/remove ❤️ reaction" },
            react_eyes = { lhs = "<space>re", desc = "add/remove 👀 reaction" },
            react_thumbs_up = { lhs = "<space>r+", desc = "add/remove 👍 reaction" },
            react_thumbs_down = { lhs = "<space>r-", desc = "add/remove 👎 reaction" },
            react_rocket = { lhs = "<space>rr", desc = "add/remove 🚀 reaction" },
            react_laugh = { lhs = "<space>rl", desc = "add/remove 😄 reaction" },
            react_confused = { lhs = "<space>rc", desc = "add/remove 😕 reaction" },
          },
          pull_request = {
            checkout_pr = { lhs = "<space>po", desc = "checkout PR" },
            merge_pr = { lhs = "<space>pm", desc = "merge commit PR" },
            squash_and_merge_pr = { lhs = "<space>psm", desc = "squash and merge PR" },
            list_commits = { lhs = "<space>pc", desc = "list PR commits" },
            list_changed_files = { lhs = "<space>pf", desc = "list PR changed files" },
            show_pr_diff = { lhs = "<space>pd", desc = "show PR diff" },
            add_reviewer = { lhs = "<space>va", desc = "add reviewer" },
            remove_reviewer = { lhs = "<space>vd", desc = "remove reviewer request" },
            close_issue = { lhs = "<space>ic", desc = "close PR" },
            reopen_issue = { lhs = "<space>io", desc = "reopen PR" },
            list_issues = { lhs = "<space>il", desc = "list open issues on same repo" },
            reload = { lhs = "<C-r>", desc = "reload PR" },
            open_in_browser = { lhs = "<C-b>", desc = "open PR in browser" },
            copy_url = { lhs = "<C-y>", desc = "copy url to system clipboard" },
            goto_file = { lhs = "gf", desc = "go to file" },
            add_assignee = { lhs = "<space>aa", desc = "add assignee" },
            remove_assignee = { lhs = "<space>ad", desc = "remove assignee" },
            create_label = { lhs = "<space>lc", desc = "create label" },
            add_label = { lhs = "<space>la", desc = "add label" },
            remove_label = { lhs = "<space>ld", desc = "remove label" },
            goto_issue = { lhs = "<space>gi", desc = "navigate to a local repo issue" },
            add_comment = { lhs = "<space>ca", desc = "add comment" },
            delete_comment = { lhs = "<space>cd", desc = "delete comment" },
            next_comment = { lhs = "]c", desc = "go to next comment" },
            prev_comment = { lhs = "[c", desc = "go to previous comment" },
            react_hooray = { lhs = "<space>rp", desc = "add/remove 🎉 reaction" },
            react_heart = { lhs = "<space>rh", desc = "add/remove ❤️ reaction" },
            react_eyes = { lhs = "<space>re", desc = "add/remove 👀 reaction" },
            react_thumbs_up = { lhs = "<space>r+", desc = "add/remove 👍 reaction" },
            react_thumbs_down = { lhs = "<space>r-", desc = "add/remove 👎 reaction" },
            react_rocket = { lhs = "<space>rr", desc = "add/remove 🚀 reaction" },
            react_laugh = { lhs = "<space>rl", desc = "add/remove 😄 reaction" },
            react_confused = { lhs = "<space>rc", desc = "add/remove 😕 reaction" },
          },
        },
      })
    end,
    keys = {
      { "<leader>O", "<cmd>Octo<cr>", desc = "Octo" },
    },
  },
}