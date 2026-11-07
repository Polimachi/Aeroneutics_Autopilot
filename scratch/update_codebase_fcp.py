import os

# 1. Update src/2_guidance/fcp/fcp_runtime.lua
p = 'src/2_guidance/fcp/fcp_runtime.lua'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace('-- src/sas_runtime.lua', '-- src/fcp_runtime.lua')
c = c.replace('sas_runtime', 'fcp_runtime')
c = c.replace('lastActiveSource = "SAS"', 'lastActiveSource = "FCP"')
c = c.replace('activeSource = "SAS"', 'activeSource = "FCP"')
c = c.replace('activeSource = ctx.lastActiveSource or "SAS"', 'activeSource = ctx.lastActiveSource or "FCP"')
with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Updated fcp_runtime.lua')

# 2. Update src/2_guidance/fcp/modules/channel_sentinel.lua
p = 'src/2_guidance/fcp/modules/channel_sentinel.lua'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace('occupantId = "SAS"', 'occupantId = "FCP"')
with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Updated channel_sentinel.lua')

# 3. Update src/2_guidance/fcp/modules/flight_fsm.lua
p = 'src/2_guidance/fcp/modules/flight_fsm.lua'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace('activeSource ~= "SAS"', 'activeSource ~= "FCP"')
c = c.replace('activeSource == "SAS"', 'activeSource == "FCP"')
c = c.replace('RESUME_UAP_CONTROL', 'RESUME_FCP_CONTROL')
with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Updated flight_fsm.lua')

# 4. Update src/2_guidance/fcp/modules/guidance_controller.lua
p = 'src/2_guidance/fcp/modules/guidance_controller.lua'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace('source = "SAS"', 'source = "FCP"')
with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Updated guidance_controller.lua')

# 5. Update src/2_guidance/fcp/modules/network_manager.lua
p = 'src/2_guidance/fcp/modules/network_manager.lua'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace('hardwareUuid = sys.hardwareUuid or "SAS-04"', 'hardwareUuid = sys.hardwareUuid or "FCP-04"')
with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Updated network_manager.lua')

# 6. Update src/2_guidance/fcp/modules/operator_handler.lua
p = 'src/2_guidance/fcp/modules/operator_handler.lua'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace('source = state and state.authority or "SAS"', 'source = state and state.authority or "FCP"')
with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Updated operator_handler.lua')

# 7. Update src/2_guidance/fcp/modules/ui_renderer.lua
p = 'src/2_guidance/fcp/modules/ui_renderer.lua'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace('SAS NODE-04', 'FCP NODE-04')
with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Updated ui_renderer.lua')

# 8. Update src/2_guidance/fcp/modules/drivers/
for d in ['drone_driver.lua', 'fixed_wing_driver.lua', 'helicopter_driver.lua']:
    dp = os.path.join('src/2_guidance/fcp/modules/drivers', d)
    if os.path.exists(dp):
        with open(dp, 'r', encoding='utf-8') as f:
            c = f.read()
        c = c.replace('UAFS SAS Layer 2:', 'UAFS FCP Layer 2:')
        with open(dp, 'w', encoding='utf-8') as f:
            f.write(c)
        print(f'Updated {d}')

# 9. Update src/2_guidance/fcp/node_vas_sim.lua
p = 'src/2_guidance/fcp/node_vas_sim.lua'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace('activeSource = "SAS"', 'activeSource = "FCP"')
with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Updated node_vas_sim.lua')

# 10. Update src/1_control/vas/modules/state_machine.lua
p = 'src/1_control/vas/modules/state_machine.lua'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace('activeSource = "SAS"', 'activeSource = "FCP"')
c = c.replace('state.activeSource = "SAS"', 'state.activeSource = "FCP"')
with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Updated vas/state_machine.lua')

# 11. Update src/1_control/vas/modules/telemetry_feeder.lua
p = 'src/1_control/vas/modules/telemetry_feeder.lua'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace('activeSource = fsmState.activeSource or "SAS"', 'activeSource = fsmState.activeSource or "FCP"')
with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Updated vas/telemetry_feeder.lua')

# 12. Update src/1_control/vas/node_fcp.lua
p = 'src/1_control/vas/node_fcp.lua'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace('Mock Node 04: UAP (Unmanned Autonomous Pilot)', 'Mock Node 04: FCP (Flight Control Program)')
c = c.replace('source = "SAS"', 'source = "FCP"')
with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Updated vas/node_fcp.lua')

# 13. Update src/README.md
p = 'src/README.md'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace('sas/: **SAS** (Stability Augmentation System) - 안정성 향상 및 자율 항법 시스템', 'fcp/: **FCP** (Flight Control Program) - 비행 제어 프로그램 및 외루프 유도 컴퓨터')
with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Updated src/README.md')

# 14. Update tests/2_guidance/fcp/test_fcp_core.lua
p = 'tests/2_guidance/fcp/test_fcp_core.lua'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace('2_guidance/sas', '2_guidance/fcp')
c = c.replace('sas config file staging and access', 'fcp config file staging and access')
c = c.replace('config/sas_config.json', 'config/fcp_config.json')
c = c.replace('sas flight FSM state transitions and failsafes', 'fcp flight FSM state transitions and failsafes')
with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Updated test_fcp_core.lua')

# 15. Update tests/harness/test_cli_runner.py
p = 'tests/harness/test_cli_runner.py'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace('("2_guidance/sas", "SAS_UI")', '("2_guidance/fcp", "FCP_UI")')
c = c.replace('"2_guidance/sas": "PASS"', '"2_guidance/fcp": "PASS"')
with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Updated test_cli_runner.py')
