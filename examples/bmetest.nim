# Silly test to check that communication works, tested on the Arduino Uno and
# the Digispark (Attiny85).
import board
import board / [times, progmem]
import bme280

I2cBus.init()
Led.output()

const sensor = Bme280Device(bus: I2cBus, address: 0x76 shl 1)
var
  temperature: int32
  humidity: int32
  pressure: int32

while true:
  sensor.start(wait = false)
  delayMs(1000)
  sensor.readRaw(temperature, humidity, pressure)
  if temperature < 550000:
    Led.low()
  else:
    Led.high()
  delayMs(1000)

