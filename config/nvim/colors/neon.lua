-- Neon — custom high-contrast dark colorscheme
-- Vibrant neon colors on a near-black background

vim.cmd('highlight clear')
if vim.fn.exists('syntax_on') then vim.cmd('syntax reset') end
vim.o.background = 'dark'
vim.g.colors_name = 'neon'

-- ── Palette ───────────────────────────────────────────────────────
local c = {
  bg        = 'NONE',       -- transparent
  bg_solid  = '#171717',    -- when a real bg is needed
  bg1       = '#1f1f1f',    -- cursorline, subtle highlights
  bg2       = '#252525',    -- selection secondary, UI surfaces
  bg3       = '#3a3a3a',    -- fold, inactive UI
  fg        = '#ffffff',    -- primary text
  fg_dim    = '#999999',    -- line numbers, inactive UI text
  comment   = '#5d5d5d',    -- comments

  red       = '#ff3d7f',    -- errors, unstaged changes
  red_br    = '#ff71a0',    -- bright red
  green     = '#7dff3e',    -- strings, additions
  green_br  = '#a5ff7e',    -- bright green
  yellow    = '#ffe100',    -- warnings, search, constants
  yellow_br = '#ffee6d',    -- bright yellow
  blue      = '#c76bff',    -- keywords, purple-blue
  blue_br   = '#e0a5ff',    -- bright blue
  magenta   = '#ff56d3',    -- functions, active borders, signature color
  magenta_br= '#ff94e5',    -- bright magenta
  cyan      = '#0dfff8',    -- types, info
  cyan_br   = '#84fff9',    -- bright cyan

  orange    = '#ffb52e',    -- numbers, constants
  violet    = '#de7dff',    -- special
  aqua      = '#12ffc9',    -- regex, escape
  lime      = '#caff00',    -- extra accent
  coral     = '#ff5252',    -- extra red
  sel_bg    = '#ff9ee8',    -- selection background (pastel pink)
  sel_fg    = '#000000',    -- selection foreground

  diff_add  = '#1a2e1a',    -- diff backgrounds
  diff_change = '#2e2a1a',
  diff_delete = '#2e1a1a',
  diff_text = '#3a3520',
}

local hl = function(group, opts)
  vim.api.nvim_set_hl(0, group, opts)
end

-- ── Editor UI ─────────────────────────────────────────────────────
hl('Normal',       { fg = c.fg, bg = c.bg })
hl('NormalNC',     { fg = c.fg_dim, bg = c.bg })
hl('NormalFloat',  { fg = c.fg, bg = c.bg2 })
hl('FloatBorder',  { fg = c.magenta, bg = c.bg2 })
hl('FloatTitle',   { fg = c.magenta, bg = c.bg2, bold = true })
hl('Cursor',       { fg = c.bg_solid, bg = c.magenta })
hl('CursorLine',   { bg = c.bg1 })
hl('CursorColumn', { bg = c.bg1 })
hl('CursorLineNr', { fg = c.magenta, bold = true })
hl('LineNr',       { fg = c.comment })
hl('SignColumn',   { fg = c.comment, bg = c.bg })
hl('ColorColumn',  { bg = c.bg1 })
hl('Visual',       { fg = c.sel_fg, bg = c.sel_bg })
hl('VisualNOS',    { fg = c.sel_fg, bg = c.sel_bg })
hl('Search',       { fg = c.bg_solid, bg = c.yellow })
hl('IncSearch',    { fg = c.bg_solid, bg = c.orange })
hl('CurSearch',    { fg = c.bg_solid, bg = c.yellow, bold = true })
hl('Substitute',   { fg = c.bg_solid, bg = c.red })
hl('MatchParen',   { fg = c.yellow, bg = c.bg3, bold = true })
hl('Pmenu',        { fg = c.fg, bg = c.bg2 })
hl('PmenuSel',     { fg = c.bg_solid, bg = c.magenta })
hl('PmenuSbar',    { bg = c.bg3 })
hl('PmenuThumb',   { bg = c.magenta })
hl('StatusLine',   { fg = c.fg, bg = c.bg2 })
hl('StatusLineNC', { fg = c.comment, bg = c.bg2 })
hl('TabLine',      { fg = c.fg_dim, bg = c.bg2 })
hl('TabLineFill',  { bg = c.bg2 })
hl('TabLineSel',   { fg = c.bg_solid, bg = c.magenta, bold = true })
hl('WinSeparator', { fg = c.magenta, bg = c.bg })
hl('VertSplit',    { fg = c.magenta, bg = c.bg })
hl('Folded',       { fg = c.fg_dim, bg = c.bg3 })
hl('FoldColumn',   { fg = c.comment, bg = c.bg })
hl('NonText',      { fg = c.bg3 })
hl('EndOfBuffer',  { fg = c.bg_solid })
hl('SpecialKey',   { fg = c.bg3 })
hl('Conceal',      { fg = c.comment })
hl('Directory',    { fg = c.cyan, bold = true })
hl('Title',        { fg = c.magenta, bold = true })
hl('ErrorMsg',     { fg = c.red, bold = true })
hl('WarningMsg',   { fg = c.yellow })
hl('ModeMsg',      { fg = c.fg, bold = true })
hl('MoreMsg',      { fg = c.green })
hl('Question',     { fg = c.cyan })
hl('WildMenu',     { fg = c.bg_solid, bg = c.magenta })
hl('QuickFixLine',  { bg = c.bg2, bold = true })
hl('SpellBad',     { sp = c.red, undercurl = true })
hl('SpellCap',     { sp = c.yellow, undercurl = true })
hl('SpellRare',    { sp = c.cyan, undercurl = true })
hl('SpellLocal',   { sp = c.green, undercurl = true })
hl('Whitespace',   { fg = c.bg3 })

-- ── Diff ──────────────────────────────────────────────────────────
hl('DiffAdd',    { bg = c.diff_add })
hl('DiffChange', { bg = c.diff_change })
hl('DiffDelete', { fg = c.red, bg = c.diff_delete })
hl('DiffText',   { bg = c.diff_text })

-- ── Syntax (Vim built-in groups) ──────────────────────────────────
hl('Comment',    { fg = c.comment, italic = true })
hl('Constant',   { fg = c.orange })
hl('String',     { fg = c.green })
hl('Character',  { fg = c.green })
hl('Number',     { fg = c.orange })
hl('Boolean',    { fg = c.orange, bold = true })
hl('Float',      { fg = c.orange })
hl('Identifier', { fg = c.fg })
hl('Function',   { fg = c.magenta, bold = true })
hl('Statement',  { fg = c.blue })
hl('Conditional',{ fg = c.blue })
hl('Repeat',     { fg = c.blue })
hl('Label',      { fg = c.cyan })
hl('Operator',   { fg = c.cyan })
hl('Keyword',    { fg = c.blue, italic = true })
hl('Exception',  { fg = c.red })
hl('PreProc',    { fg = c.cyan })
hl('Include',    { fg = c.blue })
hl('Define',     { fg = c.magenta })
hl('Macro',      { fg = c.magenta })
hl('PreCondit',  { fg = c.cyan })
hl('Type',       { fg = c.cyan })
hl('StorageClass', { fg = c.blue, italic = true })
hl('Structure',  { fg = c.cyan })
hl('Typedef',    { fg = c.cyan })
hl('Special',    { fg = c.violet })
hl('SpecialChar',{ fg = c.aqua })
hl('Tag',        { fg = c.red })
hl('Delimiter',  { fg = c.fg_dim })
hl('SpecialComment', { fg = c.comment, bold = true })
hl('Debug',      { fg = c.red })
hl('Underlined', { fg = c.cyan, underline = true })
hl('Bold',       { bold = true })
hl('Italic',     { italic = true })
hl('Error',      { fg = c.red, bold = true })
hl('Todo',       { fg = c.bg_solid, bg = c.yellow, bold = true })

-- ── Treesitter ────────────────────────────────────────────────────
hl('@comment',             { link = 'Comment' })
hl('@string',              { link = 'String' })
hl('@string.escape',       { fg = c.aqua })
hl('@string.regex',        { fg = c.aqua })
hl('@string.special',      { fg = c.aqua })
hl('@character',           { link = 'Character' })
hl('@number',              { link = 'Number' })
hl('@boolean',             { link = 'Boolean' })
hl('@float',               { link = 'Float' })
hl('@function',            { fg = c.magenta, bold = true })
hl('@function.builtin',    { fg = c.magenta })
hl('@function.call',       { fg = c.magenta })
hl('@function.macro',      { fg = c.magenta, italic = true })
hl('@method',              { fg = c.magenta })
hl('@method.call',         { fg = c.magenta })
hl('@constructor',         { fg = c.cyan })
hl('@parameter',           { fg = c.yellow_br })
hl('@keyword',             { fg = c.blue, italic = true })
hl('@keyword.function',    { fg = c.blue, italic = true })
hl('@keyword.operator',    { fg = c.cyan })
hl('@keyword.return',      { fg = c.blue, italic = true })
hl('@conditional',         { link = 'Conditional' })
hl('@repeat',              { link = 'Repeat' })
hl('@exception',           { link = 'Exception' })
hl('@variable',            { fg = c.fg })
hl('@variable.builtin',    { fg = c.red_br })
hl('@type',                { fg = c.cyan })
hl('@type.builtin',        { fg = c.cyan, italic = true })
hl('@type.definition',     { fg = c.cyan })
hl('@constant',            { fg = c.orange })
hl('@constant.builtin',    { fg = c.orange, bold = true })
hl('@constant.macro',      { fg = c.orange })
hl('@property',            { fg = c.cyan_br })
hl('@field',               { fg = c.cyan_br })
hl('@punctuation.delimiter', { fg = c.fg_dim })
hl('@punctuation.bracket',   { fg = c.fg })
hl('@punctuation.special',   { fg = c.cyan })
hl('@tag',                 { fg = c.red })
hl('@tag.attribute',       { fg = c.yellow })
hl('@tag.delimiter',       { fg = c.fg_dim })
hl('@operator',            { link = 'Operator' })
hl('@include',             { link = 'Include' })
hl('@namespace',           { fg = c.cyan })
hl('@label',               { link = 'Label' })
hl('@text',                { fg = c.fg })
hl('@text.strong',         { bold = true })
hl('@text.emphasis',       { italic = true })
hl('@text.underline',      { underline = true })
hl('@text.strike',         { strikethrough = true })
hl('@text.title',          { fg = c.magenta, bold = true })
hl('@text.literal',        { fg = c.green })
hl('@text.uri',            { fg = c.cyan, underline = true })
hl('@text.reference',      { fg = c.magenta })
hl('@text.todo',           { link = 'Todo' })
hl('@text.note',           { fg = c.bg_solid, bg = c.cyan, bold = true })
hl('@text.warning',        { fg = c.bg_solid, bg = c.yellow, bold = true })
hl('@text.danger',         { fg = c.bg_solid, bg = c.red, bold = true })

-- ── LSP Semantic Tokens ───────────────────────────────────────────
hl('@lsp.type.function',   { fg = c.magenta, bold = true })
hl('@lsp.type.method',     { fg = c.magenta })
hl('@lsp.type.variable',   { fg = c.fg })
hl('@lsp.type.parameter',  { fg = c.yellow_br })
hl('@lsp.type.property',   { fg = c.cyan_br })
hl('@lsp.type.class',      { fg = c.cyan, bold = true })
hl('@lsp.type.interface',  { fg = c.cyan, italic = true })
hl('@lsp.type.namespace',  { fg = c.cyan })
hl('@lsp.type.keyword',    { fg = c.blue, italic = true })
hl('@lsp.type.type',       { fg = c.cyan })
hl('@lsp.type.enum',       { fg = c.cyan })
hl('@lsp.type.enumMember', { fg = c.orange })
hl('@lsp.type.decorator',  { fg = c.violet })
hl('@lsp.type.macro',      { fg = c.magenta })
hl('@lsp.mod.deprecated',  { strikethrough = true })

-- ── Diagnostics ───────────────────────────────────────────────────
hl('DiagnosticError',           { fg = c.red })
hl('DiagnosticWarn',            { fg = c.yellow })
hl('DiagnosticInfo',            { fg = c.cyan })
hl('DiagnosticHint',            { fg = c.blue })
hl('DiagnosticOk',              { fg = c.green })
hl('DiagnosticUnderlineError',  { sp = c.red, undercurl = true })
hl('DiagnosticUnderlineWarn',   { sp = c.yellow, undercurl = true })
hl('DiagnosticUnderlineInfo',   { sp = c.cyan, undercurl = true })
hl('DiagnosticUnderlineHint',   { sp = c.blue, undercurl = true })
hl('DiagnosticUnderlineOk',     { sp = c.green, undercurl = true })
hl('DiagnosticVirtualTextError', { fg = c.red, bg = c.diff_delete })
hl('DiagnosticVirtualTextWarn',  { fg = c.yellow, bg = c.diff_change })
hl('DiagnosticVirtualTextInfo',  { fg = c.cyan, bg = c.bg2 })
hl('DiagnosticVirtualTextHint',  { fg = c.blue, bg = c.bg2 })
hl('DiagnosticSignError',       { fg = c.red })
hl('DiagnosticSignWarn',        { fg = c.yellow })
hl('DiagnosticSignInfo',        { fg = c.cyan })
hl('DiagnosticSignHint',        { fg = c.blue })
hl('LspReferenceText',          { bg = c.bg3 })
hl('LspReferenceRead',          { bg = c.bg3 })
hl('LspReferenceWrite',         { bg = c.bg3, bold = true })
hl('LspInlayHint',              { fg = c.comment, bg = c.bg1 })
hl('LspSignatureActiveParameter', { fg = c.yellow, bold = true })

-- ── Telescope ─────────────────────────────────────────────────────
hl('TelescopeNormal',        { fg = c.fg, bg = c.bg2 })
hl('TelescopeBorder',        { fg = c.magenta, bg = c.bg2 })
hl('TelescopeTitle',         { fg = c.bg_solid, bg = c.magenta, bold = true })
hl('TelescopePromptNormal',  { fg = c.fg, bg = c.bg3 })
hl('TelescopePromptBorder',  { fg = c.magenta, bg = c.bg3 })
hl('TelescopePromptTitle',   { fg = c.bg_solid, bg = c.magenta, bold = true })
hl('TelescopePromptPrefix',  { fg = c.magenta })
hl('TelescopeResultsNormal', { fg = c.fg, bg = c.bg2 })
hl('TelescopeResultsBorder', { fg = c.magenta, bg = c.bg2 })
hl('TelescopeResultsTitle',  { fg = c.bg_solid, bg = c.magenta, bold = true })
hl('TelescopePreviewNormal', { fg = c.fg, bg = c.bg2 })
hl('TelescopePreviewBorder', { fg = c.cyan, bg = c.bg2 })
hl('TelescopePreviewTitle',  { fg = c.bg_solid, bg = c.cyan, bold = true })
hl('TelescopeSelection',     { fg = c.bg_solid, bg = c.magenta, bold = true })
hl('TelescopeSelectionCaret', { fg = c.magenta })
hl('TelescopeMultiSelection', { fg = c.cyan })
hl('TelescopeMatching',      { fg = c.yellow, bold = true })

-- ── Gitsigns ──────────────────────────────────────────────────────
hl('GitSignsAdd',          { fg = c.green })
hl('GitSignsChange',       { fg = c.yellow })
hl('GitSignsDelete',       { fg = c.red })
hl('GitSignsAddNr',        { fg = c.green })
hl('GitSignsChangeNr',     { fg = c.yellow })
hl('GitSignsDeleteNr',     { fg = c.red })
hl('GitSignsAddLn',        { bg = c.diff_add })
hl('GitSignsChangeLn',     { bg = c.diff_change })
hl('GitSignsDeleteLn',     { bg = c.diff_delete })
hl('GitSignsTopdelete',    { fg = c.red })
hl('GitSignsChangedelete', { fg = c.yellow })

-- ── Diffview ──────────────────────────────────────────────────────
hl('DiffviewNormal',           { link = 'Normal' })
hl('DiffviewDim1',             { fg = c.comment })
hl('DiffviewReference',        { fg = c.cyan })
hl('DiffviewFilePanelTitle',   { fg = c.magenta, bold = true })
hl('DiffviewFilePanelCounter', { fg = c.cyan })
hl('DiffviewStatusAdded',      { fg = c.green })
hl('DiffviewStatusModified',   { fg = c.yellow })
hl('DiffviewStatusDeleted',    { fg = c.red })
hl('DiffviewStatusRenamed',    { fg = c.cyan })

-- ── Which-key ─────────────────────────────────────────────────────
hl('WhichKey',           { fg = c.magenta })
hl('WhichKeyGroup',      { fg = c.cyan })
hl('WhichKeyDesc',       { fg = c.fg })
hl('WhichKeySeparator',  { fg = c.comment })
hl('WhichKeyFloat',      { bg = c.bg2 })
hl('WhichKeyBorder',     { fg = c.magenta, bg = c.bg2 })
hl('WhichKeyValue',      { fg = c.fg_dim })

-- ── Todo Comments ─────────────────────────────────────────────────
hl('TodoFgFIX',  { fg = c.red })
hl('TodoFgHACK', { fg = c.orange })
hl('TodoFgWARN', { fg = c.yellow })
hl('TodoFgTODO', { fg = c.magenta })
hl('TodoFgNOTE', { fg = c.cyan })
hl('TodoFgPERF', { fg = c.green })
hl('TodoBgFIX',  { fg = c.bg_solid, bg = c.red, bold = true })
hl('TodoBgHACK', { fg = c.bg_solid, bg = c.orange, bold = true })
hl('TodoBgWARN', { fg = c.bg_solid, bg = c.yellow, bold = true })
hl('TodoBgTODO', { fg = c.bg_solid, bg = c.magenta, bold = true })
hl('TodoBgNOTE', { fg = c.bg_solid, bg = c.cyan, bold = true })
hl('TodoBgPERF', { fg = c.bg_solid, bg = c.green, bold = true })

-- ── Mini Statusline ───────────────────────────────────────────────
hl('MiniStatuslineModeNormal',  { fg = c.bg_solid, bg = c.magenta, bold = true })
hl('MiniStatuslineModeInsert',  { fg = c.bg_solid, bg = c.green, bold = true })
hl('MiniStatuslineModeVisual',  { fg = c.bg_solid, bg = c.cyan, bold = true })
hl('MiniStatuslineModeReplace', { fg = c.bg_solid, bg = c.red, bold = true })
hl('MiniStatuslineModeCommand', { fg = c.bg_solid, bg = c.yellow, bold = true })
hl('MiniStatuslineModeOther',   { fg = c.bg_solid, bg = c.blue, bold = true })
hl('MiniStatuslineFilename',    { fg = c.fg, bg = c.bg2 })
hl('MiniStatuslineFileinfo',    { fg = c.fg_dim, bg = c.bg2 })
hl('MiniStatuslineDevinfo',     { fg = c.fg_dim, bg = c.bg2 })
hl('MiniStatuslineInactive',    { fg = c.comment, bg = c.bg2 })

-- ── Neo-tree ──────────────────────────────────────────────────────
hl('NeoTreeNormal',        { fg = c.fg, bg = c.bg2 })
hl('NeoTreeNormalNC',      { fg = c.fg_dim, bg = c.bg2 })
hl('NeoTreeDirectoryIcon', { fg = c.cyan })
hl('NeoTreeDirectoryName', { fg = c.cyan, bold = true })
hl('NeoTreeFileName',      { fg = c.fg })
hl('NeoTreeGitAdded',      { fg = c.green })
hl('NeoTreeGitModified',   { fg = c.yellow })
hl('NeoTreeGitDeleted',    { fg = c.red })
hl('NeoTreeGitUntracked',  { fg = c.comment })
hl('NeoTreeIndentMarker',  { fg = c.bg3 })
hl('NeoTreeRootName',      { fg = c.magenta, bold = true })
hl('NeoTreeTitleBar',      { fg = c.bg_solid, bg = c.magenta, bold = true })

-- ── Bufferline ────────────────────────────────────────────────────
hl('BufferLineFill',               { bg = c.bg_solid })
hl('BufferLineBackground',         { fg = c.comment, bg = c.bg2 })
hl('BufferLineBuffer',             { fg = c.comment, bg = c.bg2 })
hl('BufferLineBufferSelected',     { fg = c.fg, bg = c.bg_solid, bold = true })
hl('BufferLineIndicatorSelected',  { fg = c.magenta, bg = c.bg_solid })
hl('BufferLineDiagnostic',         { fg = c.comment, bg = c.bg2 })
hl('BufferLineDiagnosticSelected', { fg = c.fg, bg = c.bg_solid })

-- ── Noice ─────────────────────────────────────────────────────────
hl('NoiceCmdlinePopup',       { fg = c.fg, bg = c.bg2 })
hl('NoiceCmdlinePopupBorder', { fg = c.magenta, bg = c.bg2 })
hl('NoiceCmdlineIcon',        { fg = c.magenta })
hl('NoiceConfirm',            { fg = c.fg, bg = c.bg2 })
hl('NoiceConfirmBorder',      { fg = c.cyan, bg = c.bg2 })
hl('NoiceMini',               { fg = c.fg, bg = c.bg2 })
hl('NoiceFormatProgressDone', { fg = c.bg_solid, bg = c.magenta })
hl('NoiceFormatProgressTodo', { fg = c.fg, bg = c.bg3 })

-- ── Flash ─────────────────────────────────────────────────────────
hl('FlashLabel',   { fg = c.bg_solid, bg = c.magenta, bold = true })
hl('FlashMatch',   { fg = c.cyan })
hl('FlashCurrent', { fg = c.yellow })
hl('FlashBackdrop', { fg = c.comment })

-- ── Trouble ───────────────────────────────────────────────────────
hl('TroubleNormal', { fg = c.fg, bg = c.bg2 })
hl('TroubleCount',  { fg = c.magenta, bold = true })
hl('TroubleText',   { fg = c.fg })

-- ── Harpoon ───────────────────────────────────────────────────────
hl('HarpoonWindow', { fg = c.fg, bg = c.bg2 })
hl('HarpoonBorder', { fg = c.magenta, bg = c.bg2 })

-- ── Fidget (LSP progress) ────────────────────────────────────────
hl('FidgetTitle', { fg = c.magenta })
hl('FidgetTask',  { fg = c.comment })

-- ── Copilot ──────────────────────────────────────────────────────
hl('CopilotSuggestion', { fg = c.comment })

-- ── Indent / Whitespace guides ───────────────────────────────────
hl('IblIndent',  { fg = c.bg2 })
hl('IblScope',   { fg = c.magenta })

-- ── Lazy (plugin manager) ────────────────────────────────────────
hl('LazyH1',            { fg = c.bg_solid, bg = c.magenta, bold = true })
hl('LazyButton',        { fg = c.fg, bg = c.bg3 })
hl('LazyButtonActive',  { fg = c.bg_solid, bg = c.magenta })
hl('LazySpecial',       { fg = c.cyan })
hl('LazyProgressDone',  { fg = c.magenta })
hl('LazyProgressTodo',  { fg = c.bg3 })

-- ── Mason ────────────────────────────────────────────────────────
hl('MasonNormal',            { fg = c.fg, bg = c.bg2 })
hl('MasonHeader',            { fg = c.bg_solid, bg = c.magenta, bold = true })
hl('MasonHighlight',         { fg = c.cyan })
hl('MasonHighlightBlock',    { fg = c.bg_solid, bg = c.cyan })
hl('MasonHighlightBlockBold', { fg = c.bg_solid, bg = c.magenta, bold = true })
hl('MasonMutedBlock',        { fg = c.fg_dim, bg = c.bg3 })

-- ── Markdown ─────────────────────────────────────────────────────
hl('@markup.heading.1',    { fg = c.magenta, bold = true })
hl('@markup.heading.2',    { fg = c.cyan, bold = true })
hl('@markup.heading.3',    { fg = c.green, bold = true })
hl('@markup.heading.4',    { fg = c.yellow, bold = true })
hl('@markup.heading.5',    { fg = c.blue, bold = true })
hl('@markup.heading.6',    { fg = c.violet, bold = true })
hl('@markup.link',         { fg = c.magenta })
hl('@markup.link.url',     { fg = c.cyan, underline = true })
hl('@markup.raw',          { fg = c.green })
hl('@markup.raw.block',    { fg = c.green })
hl('@markup.strong',       { bold = true })
hl('@markup.italic',       { italic = true })
hl('@markup.strikethrough', { strikethrough = true })
hl('@markup.list',         { fg = c.magenta })
