return {
  "HakonHarnes/img-clip.nvim",
  event = "VeryLazy",
  opts = {
    default = {
      dir_path = "assets",
      file_name = "%Y-%m-%d-%H-%M-%S",
      use_absolute_path = false,
      relative_to_current_file = true,
      prompt_for_file_name = false,
      show_dir_path_in_prompt = false,
      drag_and_drop = {
        enabled = true,
        insert_mode = true,
      },
    },
    filetypes = {
      markdown = {
        url_encode_path = true,
        template = "![$CURSOR]($FILE_PATH)",
        download_images = false,
      },
      tex = {
        template = "\\includegraphics[width=\\textwidth]{$FILE_PATH}",
      },
    },
  },
  keys = {
    {
      "<leader>p",
      function()
        require("img-clip").paste_image()
      end,
      desc = "Paste image from clipboard",
    },
  },
}
