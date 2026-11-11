-- tests/3_planning/amm/test_input_handler.lua
local input_handler = require("input_handler")

describe("AMM Modal Input Handler", function()
    it("starts in NAV mode and fires instant hotkeys", function()
        local h = input_handler.new()
        assert_eq(h.mode, "NAV")

        local act1 = h:handle_char("x")
        assert_not_nil(act1)
        assert_eq(act1.action, "ESTOP")

        local act2 = h:handle_char("h")
        assert_eq(act2.action, "HOLD")

        local act3 = h:handle_char("r")
        assert_eq(act3.action, "RTH")

        local act4 = h:handle_char("a")
        assert_eq(act4.action, "ARM")

        local act5 = h:handle_char("t")
        assert_eq(act5.action, "TAKEOFF")
    end)

    it("transitions to CLI mode on '/' or Enter and buffers text without triggering hotkeys", function()
        local h = input_handler.new()
        h:handle_char("/")
        assert_eq(h.mode, "CLI")

        -- Typing 'a' in CLI mode must NOT trigger ARM!
        local act = h:handle_char("a")
        assert_nil(act)
        assert_eq(h.buffer, "a")

        h:handle_char("d")
        h:handle_char("d")
        h:handle_char(" ")
        h:handle_char("1")
        h:handle_char("0")
        h:handle_char(" ")
        h:handle_char("2")
        h:handle_char("0")
        assert_eq(h.buffer, "add 10 20")
    end)

    it("parses CLI commands on Enter and returns to NAV mode", function()
        local h = input_handler.new()
        h:set_mode("CLI")
        h.buffer = "add 500 -1200 160 20 PAD_01"

        local cmd = h:handle_key(keys.enter)
        assert_not_nil(cmd)
        assert_eq(cmd.type, "COMMAND")
        assert_eq(cmd.name, "add")
        assert_eq(cmd.args[1], "500")
        assert_eq(cmd.args[2], "-1200")
        assert_eq(cmd.args[3], "160")
        assert_eq(cmd.args[4], "20")
        assert_eq(cmd.args[5], "PAD_01")
        assert_eq(h.mode, "NAV")
        assert_eq(h.buffer, "")
    end)

    it("cancels CLI edit mode on Escape", function()
        local h = input_handler.new()
        h:set_mode("CLI")
        h.buffer = "incomplete command"

        local res = h:handle_key(keys.escape or 256)
        assert_nil(res)
        assert_eq(h.mode, "NAV")
        assert_eq(h.buffer, "")
    end)

    it("handles backspace cleanly in CLI mode", function()
        local h = input_handler.new()
        h:set_mode("CLI")
        h.buffer = "alt 150"

        h:handle_key(keys.backSpace or 14)
        assert_eq(h.buffer, "alt 15")
    end)

    it("triggers emergency ESTOP even in CLI mode when Ctrl+X is pressed", function()
        local h = input_handler.new()
        h:set_mode("CLI")
        h.buffer = "typing something"

        local act = h:handle_ctrl_key("x")
        assert_not_nil(act)
        assert_eq(act.action, "ESTOP")
    end)

    it("parses v1.2.0 CLI commands (run, load, files, stop, next, mission subcommands) and handles paste in CLI mode", function()
        local h = input_handler.new()
        assert_true(input_handler.VALID_COMMANDS.run == true)
        assert_true(input_handler.VALID_COMMANDS.mission == true)
        assert_true(input_handler.VALID_COMMANDS.files == true)

        h:set_mode("CLI")
        h:handle_paste("mission run /disk/sortie_01 loop")
        local cmd_msn = h:handle_key(keys.enter or 28)
        assert_not_nil(cmd_msn)
        assert_eq(cmd_msn.name, "mission")
        assert_true(cmd_msn.known)
        assert_eq(cmd_msn.subcommand, "run")
        assert_eq(cmd_msn.subargs[1], "/disk/sortie_01")
        assert_eq(cmd_msn.subargs[2], "loop")

        h:set_mode("CLI")
        h.buffer = "files"
        local cmd_files = h:handle_key(keys.enter or 28)
        assert_eq(cmd_files.name, "files")
        assert_true(cmd_files.known)

        h:set_mode("CLI")
        h.buffer = "boguscmd"
        local cmd_unk = h:handle_key(keys.enter or 28)
        assert_eq(cmd_unk.name, "boguscmd")
        assert_false(cmd_unk.known)
    end)
end)
