import board / i2c
export i2c

type
  Bme280Device* = object
    bus*: I2c
    address*: uint8
  Mode* = enum Sleep, Force, ForceDup, Normal
  Sampling* = enum off = 0b000'u8, x1 = 0b001'u8, x2 = 0b010'u8, x4 = 0b011'u8, x8 = 0b100'u8, x16 = 0b101'u8
  Filter* = enum FilterOff = 0b000'u8, c2 = 0b010'u8, c4 = 0b011'u8, c8 = 0b100'u8, c16 = 0b101'u8
  StandBy* = enum
    us500 = (0b000'u8, "0.5")
    us62500 = (0b001'u8, "62.5")
    ms125 = (0b010'u8, "125")
    ms250 = (0b011'u8, "250")
    ms500 = (0b100'u8, "500")
    ms1000 = (0b101'u8, "1000")
    ms10 = (0b110'u8, "10")
    ms20 = (0b111'u8, "20")

proc `'sbt`*(n: string): StandBy {.compileTime.} =
  for i in StandBy:
    if $i == n:
      return i

  raise newException(ValueError, "invalid value for StandBy: " & $n)

#proc init(sensor: Bme280Device) =
#  sensor.bus.writeRegister(sensor.address, 

proc reset*(sensor: static[Bme280Device]) =
  ## Runs the power-on-reset cycle, which leaves the device in the sleep state
  ## and clears all configuration.
  sensor.bus.writeRegister(sensor.address, 0xE0, 0xB6)

proc configure*(sensor: static[Bme280Device], filter: Filter, standByTime: StandBy) =
  ## Configuration of filters and stand-by time. Stand-by time only matters for
  ## normal mode. Configuring while not in sleep mode might mean the
  ## configuration is ignored.
  sensor.bus.writeRegister(sensor.address, 0xF5,
    (standByTime.uint8 shl 4) or
    (filter.uint8 shl 1))

proc start*(sensor: static[Bme280Device]; temperature, pressure = x1, humidity: Sampling; mode = Force, wait: static[bool] = true) =
  ## Sets the mode, by default to force (one-time meassurement). Also allows
  ## setting the oversampling rate, or disabling the meassurement of part of
  ## the sensor (default is all on without oversampling). The wait parameter
  ## can be used to wait for completion of the meassurement by polling the
  ## status register.
  sensor.bus.writeRegister(sensor.address, 0xF2, humidity.uint8)
  sensor.bus.writeRegister(sensor.address, 0xF4, (temperature.uint8 shl 5) or (pressure.uint8 shl 2) or mode.uint8)

  when wait:
    while sensor.bus.readRegister(sensor.address, 0xF3) and 0b0000_1000 != 0:
      discard

proc start*(sensor: static[Bme280Device]; temperature, pressure = x1; mode = Force, wait: static[bool] = true) =
  ## Sets the mode, by default to force (one-time meassurement). Also allows
  ## setting the oversampling rate, or disabling the meassurement of part of
  ## the sensor (default is all on without oversampling). This version doesn't
  ## touch the humidity register, so humidity oversampling settings will be
  ## kept between runs, temperature and pressure are reset every time. The wait
  ## parameter can be used to wait for completion of the meassurement by polling
  ## the status register.

  sensor.bus.writeRegister(sensor.address, 0xF4, (temperature.uint8 shl 5) or (pressure.uint8 shl 2) or mode.uint8)

  when wait:
    while sensor.bus.readRegister(sensor.address, 0xF3) and 0b0000_1000 != 0:
      discard

proc readRaw*(sensor: static[Bme280Device], temperature, humidity, pressure: var int32) =
  ## Initiates the reading of raw sensor data, storing it in the given variables
  sensor.bus.start()
  sensor.bus.send(sensor.address)
  sensor.bus.send(0xF7)
  sensor.bus.stop()

  sensor.bus.start()
  sensor.bus.send(sensor.address or 0x01)
  pressure =
    (sensor.bus.recv(false).int32 shl (8 + 4)) or
    (sensor.bus.recv(false).int32 shl 4) or
    (sensor.bus.recv(false).int32 and 0b00001111)
  temperature =
    (sensor.bus.recv(false).int32 shl (8 + 4)) or
    (sensor.bus.recv(false).int32 shl 4) or
    (sensor.bus.recv(false).int32 and 0b00001111)
  humidity =
    (sensor.bus.recv(false).int32 shl (8 + 4)) or
    (sensor.bus.recv(true).int32 shl 4)
  sensor.bus.stop()
