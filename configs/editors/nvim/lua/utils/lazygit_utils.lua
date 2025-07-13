-- LazyGit Neovim Integration Utils
-- AI-powered Git operations and enhancements

local M = {}

-- Get current file path relative to git root
local function get_current_file()
  local filepath = vim.fn.expand('%:p')
  if filepath == '' then
    return nil
  end
  
  -- Get git root
  local git_root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
  if vim.v.shell_error ~= 0 then
    return nil
  end
  
  -- Return relative path
  return vim.fn.fnamemodify(filepath, ':~:.')
end

-- Check if ollama-manager is available and running
local function is_ollama_available()
  local result = vim.fn.system('command -v ollama-manager > /dev/null 2>&1 && ollama-manager status | grep -q "Service: Running"')
  return vim.v.shell_error == 0
end

-- Execute AI command with ollama-manager
local function execute_ai_command(prompt, context)
  if not is_ollama_available() then
    vim.notify("❌ Ollama not available. Run: ollama-manager setup", vim.log.levels.ERROR)
    return nil
  end
  
  local full_prompt = prompt
  if context then
    full_prompt = context .. "\n\n" .. prompt
  end
  
  local cmd = string.format('echo %s | ollama-manager chat codellama', vim.fn.shellescape(full_prompt))
  local result = vim.fn.system(cmd)
  
  if vim.v.shell_error ~= 0 then
    vim.notify("❌ AI command failed", vim.log.levels.ERROR)
    return nil
  end
  
  return result
end

-- AI Review Current File
function M.review_current_file()
  local current_file = get_current_file()
  if not current_file then
    vim.notify("⚠️  No current file or not in a git repository", vim.log.levels.WARN)
    return
  end
  
  vim.notify("🔍 AI reviewing current file: " .. current_file, vim.log.levels.INFO)
  
  -- Get file content and git diff
  local file_content = table.concat(vim.fn.readfile(vim.fn.expand('%:p')), '\n')
  local git_diff = vim.fn.system('git diff HEAD -- ' .. vim.fn.shellescape(current_file))
  
  local context = string.format([[
File: %s

Current content:
%s

Recent changes (git diff):
%s
]], current_file, file_content, git_diff)
  
  local prompt = [[
Please review this file and provide feedback on:
1. Code quality and best practices
2. Potential bugs or issues  
3. Performance improvements
4. Security considerations
5. Maintainability suggestions

Focus on actionable improvements. Be concise but specific.
]]
  
  local result = execute_ai_command(prompt, context)
  if result then
    -- Create a new buffer with the review
    vim.cmd('new')
    vim.cmd('setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile')
    vim.api.nvim_buf_set_name(0, 'AI Code Review: ' .. current_file)
    
    local review_lines = {
      '# AI Code Review: ' .. current_file,
      '## Generated on ' .. os.date('%Y-%m-%d %H:%M:%S'),
      '',
      result
    }
    
    vim.api.nvim_buf_set_lines(0, 0, -1, false, review_lines)
    vim.bo.filetype = 'markdown'
    vim.bo.modifiable = false
    
    vim.notify("✅ AI review completed", vim.log.levels.INFO)
  end
end

-- AI Commit Message Generation
function M.ai_commit_message()
  vim.notify("🤖 Generating AI commit message...", vim.log.levels.INFO)
  
  -- Check for staged changes
  local staged_files = vim.fn.systemlist('git diff --cached --name-only')
  if vim.v.shell_error ~= 0 or #staged_files == 0 then
    vim.notify("⚠️  No staged changes to commit", vim.log.levels.WARN)
    vim.notify("💡 Stage changes with: git add <files>", vim.log.levels.INFO)
    return
  end
  
  -- Get staged diff
  local staged_diff = vim.fn.system('git diff --cached')
  
  local context = string.format([[
Staged files:
%s

Staged changes:
%s
]], table.concat(staged_files, '\n'), staged_diff)
  
  local prompt = [[
Generate a concise, clear commit message following conventional commits format.

Rules:
1. Use format: type(scope): description
2. Types: feat, fix, docs, style, refactor, test, chore
3. Keep under 50 characters for the subject line
4. Be specific and descriptive
5. Use imperative mood (Add, Fix, Update, etc.)

Generate only the commit message, nothing else:
]]
  
  local result = execute_ai_command(prompt, context)
  if result then
    -- Clean up the result
    local commit_msg = result:gsub('^%s*', ''):gsub('%s*$', ''):gsub('\n.*', '')
    
    -- Show the generated message
    vim.notify("📝 Generated commit message:", vim.log.levels.INFO)
    vim.notify("   " .. commit_msg, vim.log.levels.INFO)
    
    -- Ask for confirmation
    local choice = vim.fn.confirm("Use this commit message?", "&Yes\n&No\n&Edit", 1)
    
    if choice == 1 then
      -- Use the message
      local cmd = string.format('git commit -m %s', vim.fn.shellescape(commit_msg))
      local commit_result = vim.fn.system(cmd)
      
      if vim.v.shell_error == 0 then
        vim.notify("✅ Commit created successfully", vim.log.levels.INFO)
      else
        vim.notify("❌ Commit failed: " .. commit_result, vim.log.levels.ERROR)
      end
    elseif choice == 3 then
      -- Edit the message
      local edited_msg = vim.fn.input("Edit commit message: ", commit_msg)
      if edited_msg ~= "" then
        local cmd = string.format('git commit -m %s', vim.fn.shellescape(edited_msg))
        local commit_result = vim.fn.system(cmd)
        
        if vim.v.shell_error == 0 then
          vim.notify("✅ Commit created successfully", vim.log.levels.INFO)
        else
          vim.notify("❌ Commit failed: " .. commit_result, vim.log.levels.ERROR)
        end
      end
    end
  end
end

-- Git History for Current File
function M.git_history_current_file()
  local current_file = get_current_file()
  if not current_file then
    vim.notify("⚠️  No current file or not in a git repository", vim.log.levels.WARN)
    return
  end
  
  vim.notify("📜 Loading git history for: " .. current_file, vim.log.levels.INFO)
  
  -- Get git log for current file
  local git_log = vim.fn.system(string.format(
    'git log --oneline --follow --graph --color=never -- %s | head -20',
    vim.fn.shellescape(current_file)
  ))
  
  if vim.v.shell_error ~= 0 then
    vim.notify("❌ Failed to get git history", vim.log.levels.ERROR)
    return
  end
  
  -- Create a new buffer with the history
  vim.cmd('new')
  vim.cmd('setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile')
  vim.api.nvim_buf_set_name(0, 'Git History: ' .. current_file)
  
  local history_lines = {
    '# Git History: ' .. current_file,
    '## Recent commits affecting this file',
    '',
    git_log
  }
  
  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(table.concat(history_lines, '\n'), '\n'))
  vim.bo.filetype = 'markdown'
  vim.bo.modifiable = false
  
  vim.notify("✅ Git history loaded", vim.log.levels.INFO)
end

-- FZF Git Branch Checkout
function M.git_checkout_branch()
  vim.notify("🌿 Loading git branches...", vim.log.levels.INFO)
  
  -- Get all branches
  local branches = vim.fn.systemlist('git branch -a --format="%(refname:short)"')
  if vim.v.shell_error ~= 0 then
    vim.notify("❌ Failed to get git branches", vim.log.levels.ERROR)
    return
  end
  
  -- Filter out current branch indicator and remote duplicates
  local cleaned_branches = {}
  for _, branch in ipairs(branches) do
    local clean_branch = branch:gsub('^%s*%*?%s*', ''):gsub('^origin/', '')
    if clean_branch ~= '' and not vim.tbl_contains(cleaned_branches, clean_branch) then
      table.insert(cleaned_branches, clean_branch)
    end
  end
  
  -- Use vim.ui.select for branch selection
  vim.ui.select(cleaned_branches, {
    prompt = 'Select branch to checkout:',
    format_item = function(item)
      return item
    end,
  }, function(choice)
    if choice then
      local cmd = string.format('git checkout %s', vim.fn.shellescape(choice))
      local result = vim.fn.system(cmd)
      
      if vim.v.shell_error == 0 then
        vim.notify("✅ Switched to branch: " .. choice, vim.log.levels.INFO)
        -- Refresh any open file trees
        vim.cmd('silent! NvimTreeRefresh')
      else
        vim.notify("❌ Failed to checkout branch: " .. result, vim.log.levels.ERROR)
      end
    end
  end)
end

-- Git Stash Management
function M.git_stash_manager()
  local stashes = vim.fn.systemlist('git stash list --format="%h: %s"')
  if vim.v.shell_error ~= 0 or #stashes == 0 then
    vim.notify("📦 No stashes found", vim.log.levels.INFO)
    return
  end
  
  vim.ui.select(stashes, {
    prompt = 'Select stash action:',
    format_item = function(item)
      return item
    end,
  }, function(choice)
    if choice then
      local stash_index = choice:match('^stash@{(%d+)}') or '0'
      local actions = { 'Apply', 'Pop', 'Drop', 'Show' }
      
      vim.ui.select(actions, {
        prompt = 'Action for stash:',
      }, function(action)
        if action then
          local cmd
          if action == 'Apply' then
            cmd = 'git stash apply stash@{' .. stash_index .. '}'
          elseif action == 'Pop' then
            cmd = 'git stash pop stash@{' .. stash_index .. '}'
          elseif action == 'Drop' then
            cmd = 'git stash drop stash@{' .. stash_index .. '}'
          elseif action == 'Show' then
            cmd = 'git stash show -p stash@{' .. stash_index .. '}'
          end
          
          if cmd then
            local result = vim.fn.system(cmd)
            if vim.v.shell_error == 0 then
              if action == 'Show' then
                -- Display stash content in a new buffer
                vim.cmd('new')
                vim.cmd('setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile')
                vim.api.nvim_buf_set_name(0, 'Stash: ' .. choice)
                vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(result, '\n'))
                vim.bo.filetype = 'diff'
                vim.bo.modifiable = false
              else
                vim.notify("✅ Stash " .. action:lower() .. " completed", vim.log.levels.INFO)
              end
            else
              vim.notify("❌ Stash " .. action:lower() .. " failed: " .. result, vim.log.levels.ERROR)
            end
          end
        end
      end)
    end
  end)
end

-- Interactive Rebase Helper
function M.interactive_rebase()
  -- Get recent commits for rebase selection
  local commits = vim.fn.systemlist('git log --oneline --graph -10')
  if vim.v.shell_error ~= 0 then
    vim.notify("❌ Failed to get commit history", vim.log.levels.ERROR)
    return
  end
  
  vim.ui.select(commits, {
    prompt = 'Select commit to rebase from:',
    format_item = function(item)
      return item
    end,
  }, function(choice)
    if choice then
      local commit_hash = choice:match('([a-f0-9]+)')
      if commit_hash then
        local cmd = 'git rebase -i ' .. commit_hash .. '^'
        vim.notify("🔄 Starting interactive rebase from " .. commit_hash, vim.log.levels.INFO)
        vim.fn.system('tmux new-window "' .. cmd .. '"')
      end
    end
  end)
end

-- Enhanced LazyGit integration with session management
function M.open_lazygit_with_context()
  local current_file = get_current_file()
  
  -- Set environment variables for LazyGit context
  if current_file then
    vim.env.LAZYGIT_CURRENT_FILE = current_file
  end
  
  -- Open LazyGit
  vim.cmd('LazyGit')
  
  -- Auto-refresh GitSigns after LazyGit closes
  vim.defer_fn(function()
    if vim.fn.exists(':Gitsigns') == 2 then
      vim.cmd('Gitsigns refresh')
    end
  end, 1000)
end

return M