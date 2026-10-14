-- Inline image rendering via the kitty graphics protocol (kitty, ghostty, wezterm).
-- Requires the ImageMagick CLI on the machine running nvim: `brew install imagemagick`
return {
  "3rd/image.nvim",
  build = false, -- magick_cli processor needs no luarocks build
  opts = {
    backend = "kitty",
    processor = "magick_cli",
    -- Hide images when a float (picker, completion menu, etc.) overlaps them
    window_overlap_clear_enabled = true,
    window_overlap_clear_ft_ignore = { "blink-cmp-menu", "blink-cmp-documentation", "snacks_notif" },
    max_height_window_percentage = 50,
  },
}
