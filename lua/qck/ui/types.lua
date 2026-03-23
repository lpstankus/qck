---@meta

---@alias qck.UiCategoryKey string
---@alias qck.UiCategoryLabel string
---@alias qck.UiTabId integer
---@alias qck.UiDisplayId integer

---@class qck.UiCategorySpec
---@field key qck.UiCategoryKey
---@field label qck.UiCategoryLabel

---@class qck.UiCategoryRecord
---@field key qck.UiCategoryKey
---@field label qck.UiCategoryLabel
---@field order integer
---@field tab_ids qck.UiTabId[]

---@class qck.UiTabRecord
---@field id qck.UiTabId
---@field category_key qck.UiCategoryKey
---@field category_label qck.UiCategoryLabel
---@field category_display_id qck.UiDisplayId
---@field terminal any

return {}
