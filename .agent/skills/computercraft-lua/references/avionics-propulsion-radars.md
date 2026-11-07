# Avionics, Radars & Create Propulsion APIs

Reference extracted verbatim from the project's CC:Tweaked domain specification for flight sensors, actuators, radar tracking, turret aiming, and thrusters.

## 1. CC:Avionics API

```lua
-- Create: Avionics provides CC:Tweaked peripherals for Create, Aeronautics, Simulated, and Offroad physics
local controller = peripheral.find("avionics_controller")
local radar = peripheral.find("radar")
local gimbal = peripheral.find("gimbal_sensor")
local vel = peripheral.find("velocity_sensor")
local nav = peripheral.find("navigation_table")
local laser_s = peripheral.find("laser_sensor")
local laser_p = peripheral.find("laser_pointer")
local throttle = peripheral.find("throttle_lever")
local wheel = peripheral.find("steering_wheel")
local prop = peripheral.find("propeller")
local prop_bearing = peripheral.find("propeller_bearing")
local gyro_bearing = peripheral.find("gyroscopic_propeller_bearing")
local gas = peripheral.find("gas_provider")
local wheel_mount = peripheral.find("wheel_mount")

-- 1. Avionics Controller & Transponder
controller.isTransponderOn()              -- check if transponder broadcast active (boolean)
controller.setTransponder(boolean)        -- enable/disable transponder (mainThread yield)

-- 2. Radar System
radar.getRange()                          -- returns maximum radar detection range (number)
radar.getContact()                        -- returns table of active target contact ({x, y, z, velocity, id, type} or nil)

-- 3. Instruments (Thermometer, Barometer, Hygrometer, Rain Gauge, Almanac)
instrument.getTemperature()               -- current temperature in Celsius (Thermometer)
instrument.getPressure()                  -- atmospheric pressure in hPa/bar (Barometer)
instrument.getHumidity()                  -- relative air humidity percentage (Hygrometer)
rainGauge.getRainLevel()                  -- precipitation level / rainfall rate
almanac.getDay() / almanac.getMoonPhase() -- celestial and calendar data

-- 4. Flight Attitude & Inertial Sensors
-- Gimbal Sensor (Rigid-body orientation & forces)
gimbal.getAngles()                        -- {pitch, yaw, roll} in degrees
gimbal.getAnglesRad()                     -- {pitch, yaw, roll} in radians
gimbal.getAngularRates()                  -- angular velocity body vector {wx, wy, wz} (deg/s)
gimbal.getAngularRatesRad()               -- angular velocity body vector {wx, wy, wz} (rad/s)
gimbal.getGravity()                       -- local gravity body vector {gx, gy, gz}
gimbal.getLinearAcceleration()            -- linear acceleration body vector {ax, ay, az}

-- Velocity Sensor
vel.getVelocity()                         -- world linear velocity vector {vx, vy, vz}
vel.getAirspeed()                         -- speed relative to surrounding air mass
vel.getGroundspeed()                      -- horizontal ground speed magnitude

-- Navigation Table & Laser Sensors
nav.getCoordinates()                      -- aircraft/ship global map coordinates {x, y, z}
laser_s.getDistance()                     -- rangefinder distance to target/ground (altimeter)
laser_s.hasTarget()                       -- boolean indicator of beam reflection
laser_p.setActive(boolean)                -- toggle targeting laser beam

-- 5. Aeronautics & Flight Actuators
throttle.getThrottle()                    -- current throttle setting (0.0 to 1.0)
throttle.setThrottle(value)               -- set engine throttle (0.0 to 1.0)
wheel.getSteeringAngle()                  -- steering input angle
wheel.setSteeringAngle(angle)             -- control rudder / steering angle
prop.getThrust() / prop.getRpm()          -- propeller thrust output and RPM
prop_bearing.setPitch(angle)              -- adjust variable-pitch propeller blades
prop_bearing.getPitch()                   -- current blade pitch
gyro_bearing.setGimbalAngles(pitch, yaw)  -- vector thrust gimbal steering
gas.setBurnerOutput(level)                -- hot air balloon burner heat level
gas.ventGas(amount)                       -- open steam vent / ballast release
wheel_mount.getSteering()                 -- wheel turning angle
wheel_mount.setSteering(angle)            -- steer wheel mount
wheel_mount.getSuspensionTravel()         -- suspension compression depth
```

## 2. CC:Radars API

```lua
-- Create: Radars (Create-Radar) provides radar tracking and fire control systems
local fire = peripheral.find("fire_controller")
local monitor = peripheral.find("radar_monitor") -- or connected monitor
local pitchCtrl = peripheral.find("auto_pitch_controller")
local yawCtrl = peripheral.find("auto_yaw_controller")
local radar = peripheral.find("plane_radar") or peripheral.find("radar_bearing")

-- 1. Fire Controller
fire.isPowered()                          -- returns whether controller is emitting Redstone (boolean)
fire.fireOn()                             -- activates controller and emits Redstone signal (strength 15)
fire.fireOff()                            -- deactivates controller and stops emitting Redstone
fire.setPowered(boolean)                  -- explicitly sets powered state
fire.keepFiring()                         -- pulses Redstone signal rapidly

-- 2. Radar Monitor
monitor.getSelectedTrackId()              -- returns target UUID or ship ID string
monitor.getSelectedTrack()                -- returns selected target track table (or empty table)
monitor.getTracks()                       -- returns list of all detected tracks from connected controller
-- Track Table Structure:
-- {
--   position = {x = number, y = number, z = number},
--   velocity = {x = number, y = number, z = number},
--   category = string,      -- e.g. "HOSTILE" or ""
--   id = string,            -- unique track identifier
--   scannedTime = number,   -- timestamp / tick last scanned
--   entityType = string     -- e.g. "minecraft:zombie" or ""
-- }

-- 3. Auto Pitch & Yaw Controllers (Turret Aiming)
pitchCtrl.setAngle(degrees)               -- sets target pitch angle
pitchCtrl.getAngle()                      -- returns current target pitch angle (number)
pitchCtrl.stopAuto()                      -- disconnects network auto-targeting override (irreversible until re-linked)

yawCtrl.setAngle(degrees)                 -- sets target yaw angle
yawCtrl.getAngle()                        -- returns current target yaw angle (number)
yawCtrl.stopAuto()                        -- disconnects network auto-targeting override (v0.4.3+)

-- 4. Plane Radar & Radar Bearing
radar.getTracks()                         -- returns list of detected track tables in scan range
radar.getPosition()                       -- returns radar world position table {x, y, z}
radar.getRange()                          -- returns radar scanning range in blocks (number)

-- Radar Bearing Exclusive Methods:
radar.getRotation()                       -- returns current bearing rotation angle in degrees
radar.getRotationSpeed()                  -- returns spin speed of radar bearing
radar.getDishCount()                      -- returns number of attached radar dishes/plates
```

## 3. Create Propulsion: Simulated API

```lua
-- Create Propulsion: Simulated provides rocket/space thrusters, engines, and mechanical converters
local thruster = peripheral.find("thruster")
local ion = peripheral.find("ion_thruster")
local creativeThrust = peripheral.find("creative_thruster")
local vec = peripheral.find("vector_thruster")
local lVec = peripheral.find("liquid_vector_thruster")
local cVec = peripheral.find("creative_vector_thruster")
local stirling = peripheral.find("stirling_engine")
local transmission = peripheral.find("redstone_transmission")
local tilt = peripheral.find("tilt_adapter")
local coral = peripheral.find("coral_generator")

-- 1. Standard Thruster (Fuel/Chemical)
thruster.setPower(redstonePower)          -- 0 - 15 throttle input (overrides redstone wire while attached)
thruster.setPowerNormalized(power)        -- 0.0 - 1.0 normalized throttle
thruster.getPower()                       -- current normalized throttle (0.0 - 1.0)
thruster.getObstruction()                 -- returns count of unobstructed blocks in plume path
thruster.getCurrentThrustPN()             -- real-time thrust output in pN
thruster.getCurrentThrustKN()             -- real-time thrust output in kN
thruster.getDisplayedThrustPN()           -- UI/tooltip scale thrust in pN
thruster.getDisplayedThrustKN()           -- UI/tooltip scale thrust in kN
thruster.getAirflowMs()                   -- exhaust velocity in m/s
thruster.getFuelAmountMb()                -- current stored fuel in mB
thruster.getFuelCapacityMb()              -- fuel tank capacity in mB
thruster.tanks()                          -- fluid tank info table
thruster.pushFluid(toName, limit?, fluid?) -- push fuel to adjacent fluid tank
thruster.pullFluid(fromName, limit?, fluid?) -- pull fuel from adjacent tank

-- 2. Ion Thruster (FE Electrical — Create Propulsion: Simulated)
ion.setPower(power) / ion.setPowerNormalized(power)
ion.getPower() / ion.getObstruction()
ion.getCurrentThrustPN() / ion.getCurrentThrustKN()
ion.getDisplayedThrustPN() / ion.getDisplayedThrustKN()
ion.getAirflowMs()
ion.getEnergyAmountFe()                   -- stored FE energy
ion.getEnergyCapacityFe()                 -- FE buffer capacity

-- 3. Creative Thruster
creativeThrust.setPower(power) / creativeThrust.setPowerNormalized(power)
creativeThrust.setThrustConfig(percent)   -- set scroll step (0 - 99)
creativeThrust.getThrustConfig()          -- current scroll step
creativeThrust.getTargetThrustPN() / creativeThrust.getTargetThrustKN()
creativeThrust.getCurrentThrustPN() / creativeThrust.getCurrentThrustKN()

-- 4. Vector Thruster & Liquid Vector Thruster (Gimballed Nozzle)
-- Nozzle Direction Vector (-1.0 to 1.0 plane)
vec.setVector(x, y)                       -- set 2D nozzle deflection (both clamped -1.0 to 1.0)
vec.setVectorX(x) / vec.setVectorY(y)
vec.getVectorX() / vec.getVectorY()       -- current nozzle deflection
vec.getTargetVectorX() / vec.getTargetVectorY() -- target deflection
-- Throttle Control
vec.setThrust(0-15) / vec.setThrustNormalized(0.0-1.0)
vec.setPower(0-15) / vec.setPowerNormalized(0.0-1.0) -- aliases
vec.getThrust() / vec.getPower()
-- Liquid Vector Thruster exclusive:
lVec.tanks() / lVec.pushFluid(toName, limit?, fluid?) / lVec.pullFluid(fromName, limit?, fluid?)

-- 5. Creative Vector Thruster
cVec.setThrustOutput(thrustOutputPn)      -- override base thrust in pN (pass -1 or < 0 to clear override)
cVec.clearThrustOutput()                  -- removes Lua thrust override
cVec.getMaxThrustOutputPn()               -- maximum allowable thrust override from config
cVec.isCustomThrustOutputActive()         -- boolean

-- 6. Stirling Engine & Mechanics
stirling.getRpm()                         -- engine rotational speed
stirling.setSpeed(targetSpeed)            -- set speed clamped to supported scroll tiers
stirling.setActive(boolean)               -- turn engine on/off
transmission.getTransmissionMode()        -- returns "direct" or "incremental"
transmission.setTransmissionMode(mode)    -- sets mode ("direct" / "incremental")
transmission.getShiftLevel()              -- current shift step
transmission.setShiftLevel(level)         -- set shift step
tilt.getLeftSignal() / tilt.getRightSignal() -- input signals
tilt.setTargetAngle(angle)                -- set tilt angle (computer overrides physics while connected)
coral.getCoralAmountMb() / coral.getCoralCapacityMb()
coral.getEnergyAmountFe() / coral.getEnergyCapacityFe()
```
