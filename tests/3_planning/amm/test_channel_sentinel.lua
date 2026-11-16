-- tests/3_planning/amm/test_channel_sentinel.lua
local channel_sentinel = require("channel_sentinel")

local function cleanup_lease(path)
    if fs and fs.exists and fs.exists(path) then
        fs.delete(path)
    end
end

describe("AMM channel_sentinel 40-channel validation, jittered multi-probe, boot responder, lease cache, and intrusion monitor", function()
    it("validates aligned base channels (10000..49960 step 40) and normalizes invalid base to 10000", function()
        assert_true(channel_sentinel.is_valid_base(10000))
        assert_true(channel_sentinel.is_valid_base(10040))
        assert_true(channel_sentinel.is_valid_base(49960))
        assert_false(channel_sentinel.is_valid_base(10060))
        assert_false(channel_sentinel.is_valid_base(9960))
        assert_false(channel_sentinel.is_valid_base(50000))
        assert_false(channel_sentinel.is_valid_base(49961))
        assert_false(channel_sentinel.is_valid_base(10000.5))

        local lease_path = "config/test_lease_valid.json"
        cleanup_lease(lease_path)
        local st = channel_sentinel.init({ channels = { baseChannel = 10060 } }, 1000, lease_path)
        assert_eq(st.baseChannel, 10000)
        assert_eq(st.bootstrapChannel, 50000)
        assert_eq(st.bandwidth, 40)
        cleanup_lease(lease_path)
    end)

    it("applies 0..100ms boot jitter and requires 2 clean 200ms probe rounds before ACQUIRED (MUT-03)", function()
        local lease_path = "config/test_lease_multiprobe.json"
        cleanup_lease(lease_path)

        local st = channel_sentinel.init({
            system = { domainId = "AIRCRAFT_03", hardwareUuid = "AMM-NODE-03-4402" },
            channels = { baseChannel = 10000 },
        }, 1000, lease_path)

        local boot = channel_sentinel.start_bootstrap(st, 1000)
        assert_eq(boot.type, "MSG_BLOCK_REQUEST")
        assert_eq(boot.payload.domainId, "AIRCRAFT_03")
        assert_eq(boot.payload.hardwareUuid, "AMM-NODE-03-4402")
        assert_eq(boot.payload.requestedBandwidth, 40)
        assert_eq(st.status, "GCS_WAIT")

        -- MUT-03: invalid candidate 10060 must fall back to st.baseChannel
        channel_sentinel.on_block_assign(st, { baseChannel = 10060, status = "ASSIGNED" }, 1020, function() return 0 end)
        assert_eq(st.candidateBase, 10000)

        -- Valid candidate 10040 enters JITTER_WAIT with 0..100ms delay
        channel_sentinel.on_block_assign(st, { baseChannel = 10040, status = "ASSIGNED" }, 1050, function() return 40 end)
        assert_eq(st.candidateBase, 10040)
        assert_eq(st.status, "JITTER_WAIT")
        assert_true(st.jitterDelayMs >= 0 and st.jitterDelayMs <= 100)
        assert_eq(st.jitterDelayMs, 40)

        -- Before jitter expires (1080 < 1090): no probe emitted yet
        local st_wait, pkt_wait = channel_sentinel.negotiate_and_probe(st, 1080)
        assert_eq(st_wait, "JITTER_WAIT")
        assert_nil(pkt_wait)

        -- Jitter expires (1090): emits Round 1 MSG_CHANNEL_PROBE
        local st_r1, pkt_r1 = channel_sentinel.negotiate_and_probe(st, 1090)
        assert_eq(st_r1, "PROBING")
        assert_not_nil(pkt_r1)
        assert_eq(pkt_r1.type, "MSG_CHANNEL_PROBE")
        assert_eq(pkt_r1.payload.hardwareUuid, "AMM-NODE-03-4402")
        assert_eq(pkt_r1.payload.candidateBase, 10040)
        assert_eq(pkt_r1.payload.bandwidth, 40)
        assert_eq(st.probeRound, 1)

        -- Non-conflict probe ACK must NOT lock or trigger reassign
        channel_sentinel.on_probe_ack(st, {
            type = "MSG_CHANNEL_PROBE_ACK",
            payload = { conflict = false, status = "CLEAR" },
        })
        assert_false(channel_sentinel.is_locked(st))

        -- After 200ms (1290): must NOT prematurely confirm ACQUIRED; must emit Round 2 probe
        local st_r2, pkt_r2 = channel_sentinel.negotiate_and_probe(st, 1290, {}, function() return 0 end)
        assert_eq(st_r2, "PROBING")
        assert_not_nil(pkt_r2)
        assert_eq(pkt_r2.type, "MSG_CHANNEL_PROBE")
        assert_eq(st.probeRound, 2)

        -- After second 200ms silence (1490): confirms ACQUIRED and writes lease cache
        local st_acq, pkt_acq = channel_sentinel.negotiate_and_probe(st, 1490, {})
        assert_eq(st_acq, "ACQUIRED")
        assert_nil(pkt_acq)
        assert_eq(st.baseChannel, 10040)
        assert_true(channel_sentinel.is_acquired(st))
        assert_true(fs.exists(lease_path))

        cleanup_lease(lease_path)
    end)

    it("ignores self-UUID probes and retries GCS REASSIGN_REQUEST up to 3 conflicts before LOCKED_CONFLICT", function()
        local lease_path = "config/test_lease_conflict.json"
        cleanup_lease(lease_path)

        local st = channel_sentinel.init({
            system = { domainId = "AIRCRAFT_04", hardwareUuid = "AMM-SELF-44" },
            channels = { baseChannel = 10000 },
        }, 1000, lease_path)

        channel_sentinel.on_block_assign(st, { baseChannel = 10040, status = "ASSIGNED" }, 1050, function() return 0 end)
        local _, p1 = channel_sentinel.negotiate_and_probe(st, 1050)
        assert_eq(p1.type, "MSG_CHANNEL_PROBE")

        -- Self-UUID incoming probe must return nil (no self-conflict)
        local self_ack = channel_sentinel.handle_incoming_probe(st, {
            type = "MSG_CHANNEL_PROBE",
            payload = { hardwareUuid = "AMM-SELF-44", candidateBase = 10040, bandwidth = 40 },
        })
        assert_nil(self_ack)

        -- Conflict 1 -> REASSIGN_REQUEST (not LOCKED_CONFLICT), emits MSG_BLOCK_REQUEST(conflictBase = 10040)
        channel_sentinel.on_probe_ack(st, {
            type = "MSG_CHANNEL_PROBE_ACK",
            payload = { conflict = true, status = "CONFLICT_DETECTED", occupiedBase = 10040, responderUuid = "OTHER-1" },
        })
        assert_eq(st.status, "REASSIGN_REQUEST")
        assert_false(channel_sentinel.is_locked(st))
        local st_req1, req1 = channel_sentinel.negotiate_and_probe(st, 1100)
        assert_eq(st_req1, "GCS_WAIT")
        assert_eq(req1.type, "MSG_BLOCK_REQUEST")
        assert_eq(req1.payload.conflictBase, 10040)

        -- Conflict 2 -> still REASSIGN_REQUEST (attempt 2 < 3)
        channel_sentinel.on_block_assign(st, { baseChannel = 10080, status = "REASSIGNED" }, 1150, function() return 0 end)
        channel_sentinel.negotiate_and_probe(st, 1150)
        channel_sentinel.on_probe_ack(st, {
            type = "MSG_CHANNEL_PROBE_ACK",
            payload = { conflict = true, status = "CONFLICT_DETECTED", occupiedBase = 10080, responderUuid = "OTHER-2" },
        })
        assert_eq(st.status, "REASSIGN_REQUEST")
        assert_false(channel_sentinel.is_locked(st))
        local st_req2, req2 = channel_sentinel.negotiate_and_probe(st, 1200)
        assert_eq(st_req2, "GCS_WAIT")
        assert_eq(req2.payload.conflictBase, 10080)

        -- Conflict 3 -> LOCKED_CONFLICT (attempt >= 3)
        channel_sentinel.on_block_assign(st, { baseChannel = 10120, status = "REASSIGNED" }, 1250, function() return 0 end)
        channel_sentinel.negotiate_and_probe(st, 1250)
        channel_sentinel.on_probe_ack(st, {
            type = "MSG_CHANNEL_PROBE_ACK",
            payload = { conflict = true, status = "CONFLICT_DETECTED", occupiedBase = 10120, responderUuid = "OTHER-3" },
        })
        assert_eq(st.status, "LOCKED_CONFLICT")
        assert_true(channel_sentinel.is_locked(st))

        -- GCS DENIED / FAILED directly locks LOCKED_CONFLICT
        local st_den = channel_sentinel.init({ system = { hardwareUuid = "AMM-DENY" } }, 1000, lease_path)
        channel_sentinel.on_block_assign(st_den, { status = "DENIED", reason = "INVALID" }, 1050)
        assert_eq(st_den.status, "LOCKED_CONFLICT")
        assert_true(channel_sentinel.is_locked(st_den))

        cleanup_lease(lease_path)
    end)

    it("responds immediately to foreign MSG_CHANNEL_PROBE in BOOT_VERIFY, DISARMED, and PROBING states", function()
        local lease_path = "config/test_lease_responder.json"
        cleanup_lease(lease_path)

        local st = channel_sentinel.init({
            system = { domainId = "AIRCRAFT_01", hardwareUuid = "AMM-RESPONDER-01" },
            channels = { baseChannel = 10000 },
        }, 1000, lease_path)

        for _, status_name in ipairs({ "BOOT_VERIFY", "DISARMED", "PROBING" }) do
            st.status = status_name
            st.baseChannel = 10000
            st.candidateBase = 10000
            local ack = channel_sentinel.handle_incoming_probe(st, {
                type = "MSG_CHANNEL_PROBE",
                payload = { hardwareUuid = "OTHER", candidateBase = 10000, bandwidth = 40 },
            })
            assert_not_nil(ack, "Expected conflict ACK in status " .. status_name)
            assert_eq(ack.type, "MSG_CHANNEL_PROBE_ACK")
            assert_eq(ack.payload.status, "CONFLICT_DETECTED")
            assert_eq(ack.payload.occupiedBase, 10000)
            assert_eq(ack.payload.responderUuid, "AMM-RESPONDER-01")
        end

        cleanup_lease(lease_path)
    end)

    it("persists local lease cache, revalidates on reboot, accepts GCS REASSIGNED, and enforces offline policy", function()
        local lease_path = "config/test_lease_cache.json"
        cleanup_lease(lease_path)

        -- 1. Acquire 10000 and persist lease cache
        local st1 = channel_sentinel.init({
            system = { domainId = "AIRCRAFT_05", hardwareUuid = "AMM-UUID-05" },
        }, 1000, lease_path)
        st1.baseChannel = 10000
        st1.status = "ACQUIRED"
        assert_true(channel_sentinel.save_lease_cache(st1, lease_path))
        assert_true(fs.exists(lease_path))

        -- 2. Reboot loads cachedBase=10000 and sends preferredBase=10000; GCS REASSIGNED=10080 overrides cache
        local st2 = channel_sentinel.init({
            system = { domainId = "AIRCRAFT_05", hardwareUuid = "AMM-UUID-05" },
        }, 2000, lease_path)
        assert_eq(st2.cachedBase, 10000)
        assert_eq(st2.status, "BOOT_VERIFY")
        local req = channel_sentinel.start_bootstrap(st2, 2000)
        assert_eq(req.payload.preferredBase, 10000)

        channel_sentinel.on_block_assign(st2, { baseChannel = 10080, status = "REASSIGNED" }, 2050, function() return 0 end)
        channel_sentinel.negotiate_and_probe(st2, 2050)
        channel_sentinel.negotiate_and_probe(st2, 2250, {}, function() return 0 end)
        local final_st = channel_sentinel.negotiate_and_probe(st2, 2450, {})
        assert_eq(final_st, "ACQUIRED")
        assert_eq(st2.baseChannel, 10080)

        -- 3. GCS offline timeout with cachedBase -> probes cachedBase -> ACQUIRED_OFFLINE + NO_GCS_LEASE
        local st3 = channel_sentinel.init({
            system = { domainId = "AIRCRAFT_05", hardwareUuid = "AMM-UUID-05" },
        }, 3000, lease_path)
        assert_eq(st3.cachedBase, 10080)
        channel_sentinel.start_bootstrap(st3, 3000)
        local st3_to, p_off1 = channel_sentinel.negotiate_and_probe(st3, 5000, {}, function() return 0 end)
        assert_eq(st3_to, "PROBING")
        assert_eq(p_off1.payload.candidateBase, 10080)
        channel_sentinel.negotiate_and_probe(st3, 5200, {}, function() return 0 end)
        local st3_fin = channel_sentinel.negotiate_and_probe(st3, 5400, {})
        assert_eq(st3_fin, "ACQUIRED_OFFLINE")
        assert_eq(st3.offlineWarning, "NO_GCS_LEASE")
        assert_false(channel_sentinel.is_locked(st3))
        assert_true(channel_sentinel.is_acquired(st3))

        -- 4. GCS offline timeout WITHOUT cachedBase -> LOCKED_NO_GCS
        cleanup_lease(lease_path)
        local st4 = channel_sentinel.init({
            system = { domainId = "AIRCRAFT_06", hardwareUuid = "AMM-UUID-06" },
        }, 4000, lease_path)
        assert_nil(st4.cachedBase)
        channel_sentinel.start_bootstrap(st4, 4000)
        local st4_to = channel_sentinel.negotiate_and_probe(st4, 6000)
        assert_eq(st4_to, "LOCKED_NO_GCS")
        assert_true(channel_sentinel.is_locked(st4))
        assert_false(channel_sentinel.is_acquired(st4))

        cleanup_lease(lease_path)
    end)

    it("tracks foreign domainId intrusion across Base+0..39 and escalates at 30000ms", function()
        local lease_path = "config/test_lease_intrusion.json"
        cleanup_lease(lease_path)

        local st = channel_sentinel.init({
            system = { domainId = "AIRCRAFT_01", hardwareUuid = "AMM-01" },
            channels = { baseChannel = 10000 },
        }, 1000, lease_path)
        st.status = "ACQUIRED"
        st.baseChannel = 10000

        -- Own domainId & out-of-block channels do not count
        local hit_own, _ = channel_sentinel.record_intrusion_sample(st, 10010, "AIRCRAFT_01", 1000)
        assert_false(hit_own)
        local hit_ext, _ = channel_sentinel.record_intrusion_sample(st, 10040, "OTHER_CRAFT", 1000)
        assert_false(hit_ext)
        assert_eq(st.intrusionCount, 0)

        -- Foreign packets inside Base+0..39 trigger INTRUSION_DETECTED
        local hit1, r1 = channel_sentinel.record_intrusion_sample(st, 10008, "OTHER_CRAFT", 1000)
        assert_true(hit1)
        assert_eq(r1, "INTRUSION_DETECTED")
        local hit2, r2 = channel_sentinel.record_intrusion_sample(st, 10039, "OTHER_CRAFT", 15000)
        assert_true(hit2)
        assert_eq(r2, "INTRUSION_DETECTED")
        assert_eq(st.intrusionCount, 2)

        -- At >= 30,000ms continuous intrusion -> FAILSAFE_ESCALATE
        local hit3, r3 = channel_sentinel.record_intrusion_sample(st, 10020, "OTHER_CRAFT", 31000)
        assert_true(hit3)
        assert_eq(r3, "FAILSAFE_ESCALATE")
        assert_eq(channel_sentinel.step_intrusion_watchdog(st, 31050), "FAILSAFE_ESCALATE")

        cleanup_lease(lease_path)
    end)

    it("handles 2-phase rebind PREPARE -> COMMIT and 500ms timeout ROLLBACK", function()
        local lease_path = "config/test_lease_rebind.json"
        cleanup_lease(lease_path)

        local st = channel_sentinel.init({ channels = { baseChannel = 10000 } }, 1000, lease_path)
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

        cleanup_lease(lease_path)
    end)
end)
