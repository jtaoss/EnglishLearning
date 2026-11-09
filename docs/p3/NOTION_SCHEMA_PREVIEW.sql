-- Preview only. Requires approval of notion-preview-200.json before execution.
-- Execution record: approved and applied on 2026-11-09; see NOTION_IMPORT_STATISTICS.json.
-- Notion MCP update_data_source statements, with data_source_id supplied separately:
-- collection://157d89e5-71fb-4e68-9640-1b04dbb1e627
-- Personal learning properties and existing page identities are excluded.
ADD COLUMN "拼读提示" RICH_TEXT;
ADD COLUMN "音节说明" RICH_TEXT;
ADD COLUMN "重音说明" RICH_TEXT;
ADD COLUMN "拼读复核说明" RICH_TEXT;
ADD COLUMN "音频许可状态" RICH_TEXT;
ADD COLUMN "标准音频来源" RICH_TEXT;
ADD COLUMN "标准音频许可" RICH_TEXT;
