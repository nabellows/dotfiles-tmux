vim.api.nvim_create_autocmd({"BufRead", "BufNewFile"}, {
    pattern = "*.conf",
    callback = function()
        vim.bo.filetype = "tmux"
        -- Super silly, leave tmux highlighting as possible in general (for injections in shell), but prefer the nvim highlighting as the treesitter is broken in lots of cases
        -- vim.cmd.TSBufDisable"highlight"
    end
})
