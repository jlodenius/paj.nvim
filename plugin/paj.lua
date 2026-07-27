if vim.g.loaded_paj_nvim then
  return
end
vim.g.loaded_paj_nvim = true

require("paj").setup()
