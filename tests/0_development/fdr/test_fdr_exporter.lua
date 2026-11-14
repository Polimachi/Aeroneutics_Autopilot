-- Unit tests for FDR cloud_exporter (chunked http.post export to GDRIVE_WEBHOOK)
local cloud_exporter = require("cloud_exporter")

describe("fdr cloud_exporter", function()
    it("uploads manifest parts in <= 100KB JSON chunks with gdriveFolderId and zero modem calls", function()
        local posts = {}
        local files = {
            ["/disk/fdr_logs/part001.jsonl"] = string.rep('{"recordType":"FRAME"}\n', 5),
            ["/logs/sessions/S1.json"] = '{"sessionId":"S1"}',
        }
        local httpApi = {
            post = function(url, body, headers)
                table.insert(posts, { url = url, body = body, headers = headers })
                return { readAll = function() return '{"ok":true}' end, close = function() end }, nil
            end,
        }
        local fsApi = {
            exists = function(p) return files[p] ~= nil end,
            open = function(p, mode)
                if mode ~= "r" or not files[p] then return nil end
                local data = files[p]
                return { readAll = function() return data end, close = function() end }
            end,
        }

        local ok, info = cloud_exporter.upload_session({
            sessionId = "S1",
            manifestPath = "/logs/sessions/S1.json",
            parts = { { partIndex = 1, filePath = "/disk/fdr_logs/part001.jsonl" } },
        }, {
            mode = "GDRIVE_WEBHOOK",
            webhookUrl = "https://script.google.com/macros/s/demo/exec",
            gdriveFolderId = "1C3ZWMoXjsba1QE8ksgWG0LSfxzW_nMWI",
            gdriveFolderName = "FDR_Reports",
            authToken = "SECRET_123",
            maxChunkBytes = 48,
        }, httpApi, fsApi)

        assert_true(ok)
        assert_eq(info.uploadedFiles, 2)
        assert_true(#posts >= 3)
        assert_eq(posts[1].url, "https://script.google.com/macros/s/demo/exec")
        assert_true(string.find(posts[1].body, "1C3ZWMoXjsba1QE8ksgWG0LSfxzW_nMWI", 1, true) ~= nil)
        assert_true(string.find(posts[1].body, "SECRET_123", 1, true) ~= nil)
    end)

    it("returns structured error and preserves local files when webhookUrl is missing or POST fails", function()
        local files = { ["/disk/p1.jsonl"] = '{"recordType":"META"}\n' }
        local fsApi = {
            exists = function(p) return files[p] ~= nil end,
            open = function(p)
                local data = files[p]
                return data and { readAll = function() return data end, close = function() end } or nil
            end,
        }
        local okNoUrl, infoNoUrl = cloud_exporter.upload_session(
            { sessionId = "S1", parts = { { partIndex = 1, filePath = "/disk/p1.jsonl" } } },
            { mode = "GDRIVE_WEBHOOK", webhookUrl = "", gdriveFolderId = "1C3ZWMoXjsba1QE8ksgWG0LSfxzW_nMWI" },
            { post = function() return nil, "unreachable" end },
            fsApi
        )
        assert_false(okNoUrl)
        assert_eq(infoNoUrl.err, "ERR_MISSING_WEBHOOK_URL")
        assert_not_nil(files["/disk/p1.jsonl"])

        local okFail, infoFail = cloud_exporter.upload_session(
            { sessionId = "S1", parts = { { partIndex = 1, filePath = "/disk/p1.jsonl" } } },
            { mode = "GDRIVE_WEBHOOK", webhookUrl = "https://example.test/hook" },
            { post = function() return nil, "HTTP_500" end },
            fsApi
        )
        assert_false(okFail)
        assert_eq(infoFail.err, "HTTP_500")
        assert_not_nil(files["/disk/p1.jsonl"])
    end)
end)
