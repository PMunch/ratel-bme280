import board / i2c
export i2c

type
  Bme280Device* = object
    bus*: I2c
    address*: uint8
  Bme280*[device: static[Bme280Device]] = object
    # Numbers are the position in the data array used for reading
    digT1*: uint16 #  0- 1
    digT2*: int16  #  2- 3
    digT3*: int16  #  4- 5
    digP1*: uint16 #  6- 7
    digP2*: int16  #  8- 9
    digP3*: int16  # 10-11
    digP4*: int16  # 12-13
    digP5*: int16  # 14-15
    digP6*: int16  # 16-17
    digP7*: int16  # 18-19
    digP8*: int16  # 20-21
    digP9*: int16  # 22-23
    digH1*: uint8  # 24
    digH2*: int16  # 25-26
    digH3*: uint8  # 27
    digH4*: int16  # 28-29
    digH5*: int16  # 30-31
    digH6*: int8   # 32
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

proc init*(sensor: var Bme280) =
  sensor.device.bus.start()
  sensor.device.bus.send(sensor.device.address)
  sensor.device.bus.send(0x88)
  sensor.device.bus.stop()

  sensor.device.bus.start()
  sensor.device.bus.send(sensor.device.address or 0x01)
  var data = cast[ptr array[32, uint8]](sensor.digT1.addr)
  for i in 0..<24:
    data[i] = sensor.device.bus.recv(false)
  discard sensor.device.bus.recv(false)
  data[24] = sensor.device.bus.recv(true)
  sensor.device.bus.stop()

  sensor.device.bus.start()
  sensor.device.bus.send(sensor.device.address)
  sensor.device.bus.send(0xE1)
  sensor.device.bus.stop()

  sensor.device.bus.start()
  sensor.device.bus.send(sensor.device.address or 0x01)
  for i in 25..30:
    data[i] = sensor.device.bus.recv(false)

  let d29 = data[29].int16
  sensor.digH4 = (data[28].int16 shl 4) or (0x0f'i16 and d29)
  sensor.digH5 = (data[30].int16 shl 4) or ((d29 shr 4) and 0x0f'i16)
  sensor.digH6 = sensor.device.bus.recv(true).int8
  sensor.device.bus.stop()

proc reset*(sensor: Bme280) =
  ## Runs the power-on-reset cycle, which leaves the device in the sleep state
  ## and clears all configuration.
  sensor.device.bus.writeRegister(sensor.device.address, 0xE0, 0xB6)

proc configure*(sensor: Bme280, filter: Filter, standByTime: StandBy) =
  ## Configuration of filters and stand-by time. Stand-by time only matters for
  ## normal mode. Configuring while not in sleep mode might mean the
  ## configuration is ignored.
  sensor.device.bus.writeRegister(sensor.device.address, 0xF5,
    (standByTime.uint8 shl 4) or
    (filter.uint8 shl 1))

proc start*(sensor: Bme280; temperature, pressure = x1, humidity: Sampling; mode = Force, wait: static[bool] = true) =
  ## Sets the mode, by default to force (one-time meassurement). Also allows
  ## setting the oversampling rate, or disabling the meassurement of part of
  ## the sensor (default is all on without oversampling). The wait parameter
  ## can be used to wait for completion of the meassurement by polling the
  ## status register.
  sensor.device.bus.writeRegister(sensor.device.address, 0xF2, humidity.uint8)
  sensor.device.bus.writeRegister(sensor.device.address, 0xF4, (temperature.uint8 shl 5) or (pressure.uint8 shl 2) or mode.uint8)

  when wait:
    while sensor.device.bus.readRegister(sensor.device.address, 0xF3) and 0b0000_1000 != 0:
      discard

proc start*(sensor: Bme280; temperature, pressure = x1; mode = Force, wait: static[bool] = true) =
  ## Sets the mode, by default to force (one-time meassurement). Also allows
  ## setting the oversampling rate, or disabling the meassurement of part of
  ## the sensor (default is all on without oversampling). This version doesn't
  ## touch the humidity register, so humidity oversampling settings will be
  ## kept between runs, temperature and pressure are reset every time. The wait
  ## parameter can be used to wait for completion of the meassurement by polling
  ## the status register.
  sensor.device.bus.writeRegister(sensor.device.address, 0xF4, (temperature.uint8 shl 5) or (pressure.uint8 shl 2) or mode.uint8)

  when wait:
    while sensor.device.bus.readRegister(sensor.device.address, 0xF3) and 0b0000_1000 != 0:
      discard

template compensateTemp*(digT1: uint16, digT2, digT3: int16, tfine, temp: var int32) =
  var var1, var2: int32
  var1 = (((cast[uint32](temp) shr 3).int32 - (digT1.int32 shl 1)) * digT2) shr 11
  var2 = (((((cast[uint32](temp) shr 4).int32 - digT1.int32) * ((cast[uint32](temp) shr 4).int32 - digT1.int32)) shr 12) * digT3.int32) shr 14
  tfine = var1 + var2
  temp = (tfine * 5 + 128) shr 8

template compensatePressure*(digP1: uint16, digP2, digP3, digP4, digP5, digP6, digP7, digP8, digP9: int16, tfine: int32, pres: var uint32) =
  block:
    var var1, var2, p: int64
    var1 = tfine.int64 - 128000
    var2 = var1 * var1 * digP6.int64
    var2 = var2 + ((var1 * digP5.int64) shl 17)
    var2 = var2 + (digP4.int64 shl 35)
    var1 = ((var1 * var1 * digP3.int64) shr 8) + ((var1 * digP2.int64) shl 12)
    var1 = (((1.int64 shl 47) + var1) * dig_P1.int64) shr 33
    if var1 == 0:
      # avoid exception caused by division by zero
      break
    p = (1048576'u32 - pres).int64
    p = (((p shl 31) - var2) * 3125) div var1
    var1 = (digP9.int64 * (p shr 13) * (p shr 13)) shr 25
    var2 = (digP8.int64 * p) shr 19
    p = ((p + var1 + var2) shr 8) + (digP7.int64 shl 4)
    pres = p.uint32

template compensateHumidity*(digH1: uint8, digH2: int16, digH3: uint8, digH4, digH5: int16, digH6: int8, tfine: int32, hum: var uint32) =
  var
    inhum = 26853'u32
    tfinest = 102118'i32
  var var1: int32
  var1 = tfinest - 76800'i32
  var1 = ((((inhum.int32 shl 14'i32) - (digH4.int32 shl 20'i32) - (digH5.int32 * var1)) + 16384'i32) shr 15'i32) *
              (((((((var1 * digH6.int32) shr 10'i32) * (((var1 * digH3.int32) shr 11'i32) + 32768'i32)) shr 10'i32) + 2097152'i32) * digH2.int32 + 8192'i32) shr 14'i32)
  var1 = var1 - (((((var1 shr 15'i32) * (var1 shr 15'i32)) shr 7'i32) * digH1.int32) shr 4'i32)
  var1 = clamp(var1, 0, 419430400)
  hum = (var1 shr 12).uint32

proc read*(sensor: Bme280, temperature: var int32, humidity, pressure: var uint32) =
  ## Initiates the reading of sensor data which will be calibrated and stored
  ## in the given variables. To avoid having to bring floating point into the
  ## mix the values returned are as follows:
  ## Temperature in DegC, resolution is 0.01 DegC. Output value of “5123”
  ## equals 51.23
  ## Pressure in Pa as unsigned 32 bit integer in Q24.8 format (24 integer bits
  ## and 8 fractional bits).
  ## Output value of “24674867” represents 24674867/256 = 96386.2 Pa = 963.862 hPa
  ## Humidity in %RH as unsigned 32 bit integer in Q22.10 format (22
  ## integer and 10 fractional bits). Output value of “47445” represents
  ## 47445/1024 = 46.333 %RH
  sensor.readRaw(temperature, humidity, pressure)
  var tfine: int32
  compensateTemp(sensor.digT1, sensor.digT2, sensor.digT3, tfine, temperature)
  compensateHumidity(sensor.digH1, sensor.digH2, sensor.digH3, sensor.digH4, sensor.digH5, sensor.digH6, tfine, humidity)
  compensatePressure(sensor.digP1, sensor.digP2, sensor.digP3, sensor.digP4, sensor.digP5, sensor.digP6, sensor.digP7, sensor.digP8, sensor.digP9, tfine, pressure)

proc readReal*(sensor: Bme280, temperature, humidity, pressure: var float32) =
  ## Same as read, but returns values converted to floats in DegC, %RH, and hPa
  ## respectively
  var
    temp: int32
    hum: uint32
    pres: uint32
  sensor.readRaw(temp, hum, pres)
  var tfine: int32
  compensateTemp(sensor.digT1, sensor.digT2, sensor.digT3, tfine, temp)
  compensateHumidity(sensor.digH1, sensor.digH2, sensor.digH3, sensor.digH4, sensor.digH5, sensor.digH6, tfine, hum)
  compensatePressure(sensor.digP1, sensor.digP2, sensor.digP3, sensor.digP4, sensor.digP5, sensor.digP6, sensor.digP7, sensor.digP8, sensor.digP9, tfine, pres)
  temperature = temp.float / 100.0
  humidity = hum.float / 1024.0
  pressure = (pres.float / 256) / 100.0


proc readRaw*(sensor: Bme280, temperature: var int32, humidity, pressure: var uint32) =
  ## Initiates the reading of raw sensor data, storing it in the given variables
  sensor.device.bus.start()
  sensor.device.bus.send(sensor.device.address)
  sensor.device.bus.send(0xF7)
  sensor.device.bus.stop()

  sensor.device.bus.start()
  sensor.device.bus.send(sensor.device.address or 0x01)
  pressure =
    (sensor.device.bus.recv(false).uint32 shl (8 + 4)) or
    (sensor.device.bus.recv(false).uint32 shl 4) or
    (sensor.device.bus.recv(false).uint32 and 0b00001111)
  temperature =
    (sensor.device.bus.recv(false).int32 shl (8 + 4)) or
    (sensor.device.bus.recv(false).int32 shl 4) or
    (sensor.device.bus.recv(false).int32 and 0b00001111)
  humidity =
    (sensor.device.bus.recv(false).uint32 shl 8) or
    (sensor.device.bus.recv(true).uint32)
  sensor.device.bus.stop()
