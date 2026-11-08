-- tests/0_development/installer/test_downloader.lua
-- Unit tests for Atomic HTTP Downloader with Dual-Source & Staged Batch Rollback

local downloader = require("downloader")

local function createMockHttp(routes)
    local m = {
        _calls = {},
        _handles = {},
    }

    m.get = function(url, headers, binary)
        table.insert(m._calls, { url = url, headers = headers, binary = binary })
        local r = routes[url]
        if type(r) == "function" then
            r = r(url, headers, binary)
        end

        if not r then
            return nil, "404 Not Found"
        end

        if r.fail then
            return nil, r.error or "HTTP_REQUEST_FAILED"
        end

        local closed = false
        local handle
        handle = {
            _closed = false,
            getResponseCode = function()
                return r.code or 200
            end,
            getResponseHeaders = function()
                return r.headers or {}
            end,
            readAll = function()
                return r.body or ""
            end,
            close = function()
                closed = true
                handle._closed = true
                if r.onClose then
                    r.onClose()
                end
            end,
            isClosed = function()
                return closed
            end,
        }

        table.insert(m._handles, handle)
        return handle
    end

    return m
end

local function readFile(fsObj, path)
    if not fsObj.exists(path) then
        return nil
    end
    local h = fsObj.open(path, "r")
    if not h then
        return nil
    end
    local c = h.readAll()
    h.close()
    return c
end

local function writeFile(fsObj, path, content)
    local parent = fsObj.getDir(path)
    if parent and parent ~= "" and not fsObj.exists(parent) then
        fsObj.makeDir(parent)
    end
    local h = fsObj.open(path, "w")
    if not h then
        error("failed to open " .. path .. " for writing")
    end
    h.write(content)
    h.close()
end

describe("downloader checkHttpAvailable and HTTP API guards", function()
    it("reports HTTP_DISABLED gracefully when http API is nil", function()
        local ok, err = downloader.checkHttpAvailable(nil)
        assert_false(ok)
        assert_eq(err, "HTTP_DISABLED")

        local dummyHttp = {} -- no get function
        local ok2, err2 = downloader.checkHttpAvailable(dummyHttp)
        assert_false(ok2)
        assert_eq(err2, "HTTP_DISABLED")

        local content, fErr = downloader.fetchString("http://example.com/test", { http = dummyHttp })
        assert_nil(content)
        assert_eq(fErr, "HTTP_DISABLED")

        sdk.patch(_G, "http", nil)
        local content2, fErr2 = downloader.fetchString("http://example.com/test")
        assert_nil(content2)
        assert_eq(fErr2, "HTTP_DISABLED")
    end)
end)

describe("downloader fetchString redirect chasing, loop rejection, and Google Drive interstitial handling", function()
    it("follows 302 lowercase location redirects, closes intermediate handles, and rejects redirect loops", function()
        local initialUrl = "https://raw.githubusercontent.com/test/redirect"
        local finalUrl = "https://doc-01.googleusercontent.com/final"
        local finalBody = "return { ok = true }"

        local closedCounts = { [initialUrl] = 0, [finalUrl] = 0 }

        local routes = {
            [initialUrl] = {
                code = 302,
                headers = { location = finalUrl }, -- Lowercase header
                body = "redirecting...",
                onClose = function()
                    closedCounts[initialUrl] = closedCounts[initialUrl] + 1
                end,
            },
            [finalUrl] = {
                code = 200,
                headers = { ["content-type"] = "text/plain" },
                body = finalBody,
                onClose = function()
                    closedCounts[finalUrl] = closedCounts[finalUrl] + 1
                end,
            },
        }

        local mockHttp = createMockHttp(routes)
        local body, err = downloader.fetchString(initialUrl, { http = mockHttp })

        assert_nil(err)
        assert_eq(body, finalBody)
        assert_eq(closedCounts[initialUrl], 1, "intermediate 302 handle must be closed")
        assert_eq(closedCounts[finalUrl], 1, "final 200 handle must be closed")
        assert_eq(#mockHttp._calls, 2)
        assert_eq(mockHttp._calls[1].url, initialUrl)
        assert_eq(mockHttp._calls[2].url, finalUrl)

        -- Cyclic 302 redirect loop
        local loopUrl = "https://example.com/loop"
        local loopClosedCount = 0
        local loopRoutes = {
            [loopUrl] = {
                code = 302,
                headers = { Location = loopUrl },
                body = "loop",
                onClose = function()
                    loopClosedCount = loopClosedCount + 1
                end,
            },
        }
        local loopHttp = createMockHttp(loopRoutes)
        local loopBody, loopErr = downloader.fetchString(loopUrl, { http = loopHttp, maxRedirects = 5 })

        assert_nil(loopBody)
        assert_eq(loopErr, "TOO_MANY_REDIRECTS")
        -- Initial attempt + 5 redirects = 6 handles opened and closed
        assert_eq(loopClosedCount, 6, "all loop handles must be closed")

        -- Google Drive HTML quota/sign-in interstitial
        local gdriveUrl = "https://drive.usercontent.google.com/download?id=quota_test&export=download&confirm=t"
        local htmlBody = "<!DOCTYPE html><html><title>Google Drive - Quota exceeded</title></html>"
        local gdriveClosed = 0
        local gdriveRoutes = {
            [gdriveUrl] = {
                code = 200,
                headers = { ["content-type"] = "text/html" },
                body = htmlBody,
                onClose = function()
                    gdriveClosed = gdriveClosed + 1
                end,
            },
        }
        local gdriveHttp = createMockHttp(gdriveRoutes)
        local gdriveRes, gdriveErr = downloader.fetchString(gdriveUrl, { http = gdriveHttp })

        assert_nil(gdriveRes)
        assert_eq(gdriveErr, "GDRIVE_HTML_INTERSTITIAL")
        assert_eq(gdriveClosed, 1, "interstitial handle must be closed")
    end)

    it("extracts dynamic confirm and uuid tokens from Google Drive HTML interstitial and retries", function()
        local initialUrl = "https://drive.usercontent.google.com/download?id=big_file&export=download&confirm=t"
        local expectedRetryUrl = "https://drive.usercontent.google.com/download?id=big_file&export=download&confirm=dyn_token_abc123&uuid=uuid_test_999"
        local interstitialHtml = '<!DOCTYPE html><html><body>'
            .. '<form action="/download" method="get">'
            .. '<input type="hidden" name="id" value="big_file">'
            .. '<input type="hidden" name="confirm" value="dyn_token_abc123">'
            .. '<input type="hidden" name="uuid" value="uuid_test_999">'
            .. '</form></body></html>'
        local expectedContent = "print('successfully downloaded via confirm token')"

        local closedCounts = { [initialUrl] = 0, [expectedRetryUrl] = 0 }

        local routes = {
            [initialUrl] = {
                code = 200,
                headers = { ["content-type"] = "text/html" },
                body = interstitialHtml,
                onClose = function()
                    closedCounts[initialUrl] = (closedCounts[initialUrl] or 0) + 1
                end,
            },
            [expectedRetryUrl] = {
                code = 200,
                headers = { ["content-type"] = "text/plain" },
                body = expectedContent,
                onClose = function()
                    closedCounts[expectedRetryUrl] = (closedCounts[expectedRetryUrl] or 0) + 1
                end,
            },
        }

        local mockHttp = createMockHttp(routes)
        local body, err = downloader.fetchString(initialUrl, { http = mockHttp })

        assert_nil(err)
        assert_eq(body, expectedContent)
        assert_eq(#mockHttp._calls, 2)
        assert_eq(mockHttp._calls[1].url, initialUrl)
        assert_eq(mockHttp._calls[2].url, expectedRetryUrl)
        assert_eq(closedCounts[initialUrl], 1, "interstitial handle must be closed")
        assert_eq(closedCounts[expectedRetryUrl], 1, "retried handle must be closed")
    end)
end)

describe("downloader downloadFileAtomic temporary file and failure rollback", function()
    it("cleans up .tmp file and preserves existing destination file on mid-download failure", function()
        local destPath = sdk.temp_path("download_atomic_target.lua")
        local tmpPath = destPath .. ".tmp"

        writeFile(fs, destPath, "OLD_WORKING")
        assert_eq(readFile(fs, destPath), "OLD_WORKING")

        local failUrl = "https://example.com/fail_500"
        local failRoutes = {
            [failUrl] = {
                code = 500,
                headers = {},
                body = "Internal Server Error",
            },
        }
        local mockHttp = createMockHttp(failRoutes)

        local ok, err = downloader.downloadFileAtomic(failUrl, destPath, { http = mockHttp, fs = fs })

        assert_false(ok)
        assert_not_nil(err)
        assert_true(fs.exists(destPath), "existing destination file must remain intact")
        assert_eq(readFile(fs, destPath), "OLD_WORKING", "existing content must be untouched")
        assert_false(fs.exists(tmpPath), ".tmp file must not remain on failure")
    end)

    it("successfully writes file atomically and removes .tmp upon completion", function()
        local destPath = sdk.temp_path("download_atomic_success.lua")
        local tmpPath = destPath .. ".tmp"

        local successUrl = "https://example.com/success"
        local successRoutes = {
            [successUrl] = {
                code = 200,
                body = "print('atomic success')",
            },
        }
        local mockHttp = createMockHttp(successRoutes)

        local ok, err = downloader.downloadFileAtomic(successUrl, destPath, { http = mockHttp, fs = fs })

        assert_true(ok)
        assert_nil(err)
        assert_true(fs.exists(destPath))
        assert_eq(readFile(fs, destPath), "print('atomic success')")
        assert_false(fs.exists(tmpPath))
    end)
end)

describe("downloader downloadBatch staging and staged batch rollback", function()
    it("stages batch in /.installer_stage and rolls back entire batch if final file fails", function()
        local targetRoot = sdk.temp_path("batch_rollback_root")
        if not fs.exists(targetRoot) then
            fs.makeDir(targetRoot)
        end

        local file1 = targetRoot .. "/file1.lua"
        local file2 = targetRoot .. "/file2.lua"
        local file3 = targetRoot .. "/file3.lua"
        local stageDir = targetRoot .. "/.installer_stage"

        writeFile(fs, file1, "OLD_1")
        writeFile(fs, file2, "OLD_2")

        local entries = {
            { repoPath = "src/1_control/vas/main.lua", dest = "/file1.lua" },
            { repoPath = "src/1_control/vas/modules/actuator_adapter_tca.lua", dest = "/file2.lua" },
            { repoPath = "src/1_control/vas/modules/nav_adapter_fcp.lua", dest = "/file3.lua" },
        }

        local url1 = "https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/src/1_control/vas/main.lua"
        local url2 = "https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/src/1_control/vas/modules/actuator_adapter_tca.lua"
        local url3 = "https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/src/1_control/vas/modules/nav_adapter_fcp.lua"

        local routes = {
            [url1] = { code = 200, body = "NEW_1" },
            [url2] = { code = 200, body = "NEW_2" },
            [url3] = { fail = true, error = "404 Not Found" },
        }
        local mockHttp = createMockHttp(routes)

        local progressCalls = {}
        local opts = {
            targetRoot = targetRoot,
            http = mockHttp,
            fs = fs,
            onProgress = function(cur, total, path)
                table.insert(progressCalls, { cur = cur, total = total, path = path })
            end,
        }

        local ok, installed, err = downloader.downloadBatch("github", entries, opts)

        assert_false(ok)
        assert_nil(installed)
        assert_not_nil(err)

        -- Assert target root files retain old content
        assert_eq(readFile(fs, file1), "OLD_1")
        assert_eq(readFile(fs, file2), "OLD_2")
        assert_false(fs.exists(file3), "file3 should not exist")
        assert_false(fs.exists(stageDir), "staging directory must be completely cleaned up on rollback")

        -- Assert onProgress received calls for files
        assert_true(#progressCalls >= 2, "progress calls must be recorded")
        assert_eq(progressCalls[1].cur, 1)
        assert_eq(progressCalls[1].total, 3)
        assert_eq(progressCalls[1].path, "/file1.lua")
        assert_eq(progressCalls[2].cur, 2)
        assert_eq(progressCalls[2].total, 3)
        assert_eq(progressCalls[2].path, "/file2.lua")
    end)

    it("stages batch and commits all files atomically when all downloads succeed", function()
        local targetRoot = sdk.temp_path("batch_success_root")
        if not fs.exists(targetRoot) then
            fs.makeDir(targetRoot)
        end

        local file1 = targetRoot .. "/file1.lua"
        local file2 = targetRoot .. "/file2.lua"
        local stageDir = targetRoot .. "/.installer_stage"

        writeFile(fs, file1, "OLD_1")

        local entries = {
            { repoPath = "src/1_control/vas/main.lua", dest = "/file1.lua" },
            { repoPath = "src/1_control/vas/modules/actuator_adapter_tca.lua", dest = "/file2.lua" },
        }

        local url1 = "https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/src/1_control/vas/main.lua"
        local url2 = "https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/src/1_control/vas/modules/actuator_adapter_tca.lua"

        local routes = {
            [url1] = { code = 200, body = "NEW_1" },
            [url2] = { code = 200, body = "NEW_2" },
        }
        local mockHttp = createMockHttp(routes)

        local progressCalls = {}
        local opts = {
            targetRoot = targetRoot,
            http = mockHttp,
            fs = fs,
            onProgress = function(cur, total, path)
                table.insert(progressCalls, { cur = cur, total = total, path = path })
            end,
        }

        local ok, installed, err = downloader.downloadBatch("github", entries, opts)

        assert_true(ok)
        assert_deep_eq(installed, { "/file1.lua", "/file2.lua" })
        assert_nil(err)

        assert_eq(readFile(fs, file1), "NEW_1")
        assert_eq(readFile(fs, file2), "NEW_2")
        assert_false(fs.exists(stageDir))
        assert_eq(#progressCalls, 2)
    end)

    it("fails upfront before touching disk if any URL resolution fails", function()
        local entries = {
            { repoPath = "src/1_control/vas/main.lua", dest = "/file1.lua", gdriveId = nil },
        }

        local mockHttp = createMockHttp({})
        local ok, installed, err = downloader.downloadBatch("gdrive", entries, { http = mockHttp, fs = fs })

        assert_false(ok)
        assert_nil(installed)
        assert_eq(err, "GDRIVE_ID_UNCONFIGURED")
        assert_eq(#mockHttp._calls, 0, "no HTTP requests should be attempted when URL resolution fails")
    end)
end)
