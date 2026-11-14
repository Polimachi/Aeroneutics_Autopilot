-- tests/3_planning/amm/test_channel_sentinel.lua
local channel_sentinel = require("channel_sentinel")

describe("AMM channel_sentinel 40-channel validation, bootstrap and 4-layer rebind", function()
    it("validates aligned base channels and normalizes invalid base to 10000", function()
        assert_true(channel_sentinel.is_valid_base(10000))
        assert_true(channel_sentinel.is_valid_base(10040))
        assert_true(channel_sentinel.is_valid_base(49960))
        assert_false(channel_sentinel.is_valid_base(10060))
        assert_false(channel_sentinel.is_valid_base(9960))
        assert_false(channel_sentinel.is_valid_base(50000))

        local st = channel_sentinel.init({ channels = { baseChannel = 10060 } })
        assert_eq(st.baseChannel, 10000)
        assert_eq(st.bootstrapChannel, 50000)
        assert_eq(st.bandwidth, 40)
    end)

    it("executes MUT-03 candidate base assignment on MSG_BLOCK_ASSIGN and rejects non-conflict probe ACK", function()
        local st = channel_sentinel.init({
            system = { domainId = "AIRCRAFT_03", hardwareUuid = "AMM-NODE-03-4402" },
            channels = { baseChannel = 10000 },
        })
        local boot = channel_sentinel.start_bootstrap(st, 1000)
        assert_eq(boot.type, "MSG_BLOCK_REQUEST")
        assert_eq(boot.payload.domainId, "AIRCRAFT_03")
        assert_eq(boot.payload.hardwareUuid, "AMM-NODE-03-4402")
        assert_eq(boot.payload.requestedBandwidth, 40)

        channel_sentinel.on_block_assign(st, { baseChannel = 10040 }, 1050)
        assert_eq(st.candidateBase, 10040)
        assert_eq(st.status, "START_PROBE")

        local probe = channel_sentinel.probe_channel(st, 10040, 1060)
        assert_eq(probe.type, "MSG_CHANNEL_PROBE")
        assert_eq(probe.payload.hardwareUuid, "AMM-NODE-03-4402")
        assert_eq(probe.payload.candidateBase, 10040)
        assert_eq(probe.payload.bandwidth, 40)

        -- Non-conflict probe ACK must NOT lock arming
        channel_sentinel.on_probe_ack(st, {
            type = "MSG_CHANNEL_PROBE_ACK",
            payload = { conflict = false, status = "CLEAR" },
        })
        assert_false(channel_sentinel.is_locked(st))

        local st2, _ = channel_sentinel.negotiate_and_probe(st, 1270, {})
        assert_eq(st2, "ACQUIRED")
        assert_eq(st.baseChannel, 10040)

        -- Incoming probe targeting our acquired base returns ICD conflict ACK; conflict ACK locks arming
        local ack = channel_sentinel.handle_incoming_probe(st, {
            type = "MSG_CHANNEL_PROBE",
            payload = { hardwareUuid = "OTHER", candidateBase = 10040, bandwidth = 40 },
        })
        assert_not_nil(ack)
        assert_eq(ack.type, "MSG_CHANNEL_PROBE_ACK")
        assert_eq(ack.payload.status, "CONFLICT_DETECTED")
        assert_eq(ack.payload.occupiedBase, 10040)

        channel_sentinel.on_probe_ack(st, ack)
        assert_true(channel_sentinel.is_locked(st))
    end)

    it("handles 2-phase rebind PREPARE -> COMMIT and 500ms timeout ROLLBACK", function()
        local st = channel_sentinel.init({ channels = { baseChannel = 10000 } })
        local prep = channel_sentinel.initiate_rebind(st, 10080, 1000)
        assert_eq(prep.type, "MSG_CHANNEL_REBIND")
        assert_eq(prep.payload.action, "PREPARE")
        assert_eq(prep.payload.oldBaseChannel, 10000)
        assert_eq(prep.payload.newBaseChannel, 10080)
        assert_eq(prep.payload.bandwidth, 40)

        assert_true(channel_sentinel.on_rebind_ack(st, {
            type = "MSG_CHANNEL_REBIND_ACK",
            payload = { transactionId = prep.payload.transactionId, status = "READY" },
        }, 1100))

        local commit, c_st = channel_sentinel.step_rebind_transaction(st, 1150)
        assert_eq(c_st, "COMMITTED")
        assert_eq(commit.payload.action, "COMMIT")
        assert_eq(st.baseChannel, 10080)
        assert_nil(st.rebindTx)

        -- Timeout path
        local prep2 = channel_sentinel.initiate_rebind(st, 10120, 2000)
        assert_not_nil(prep2)
        local rb, rb_st = channel_sentinel.step_rebind_transaction(st, 2550)
        assert_eq(rb_st, "ROLLED_BACK")
        assert_eq(rb.payload.action, "ROLLBACK")
        assert_eq(st.baseChannel, 10080)
        assert_nil(st.rebindTx)
    end)
end)
