# Silly test to check that communication works, tested on the Arduino Uno and
# the Digispark (Attiny85). The Arduino Uno can calculate all the way to floats
# and print to serial. The Attiny85 can only blink the LED based on integer
# temperatures
import board
import board / [times]
import bme280

I2cBus.init()
#Serial.init(9600.Hz)
Led.output()

var
  sensor = Bme280[Bme280Device(bus: I2cBus, address: 0x76 shl 1)]()
  tfine: int32
  temperature: int32
  humidity: uint32
  pressure: uint32
  #temperature: float32
  #humidity: float32
  #pressure: float32

sensor.init()

#proc snprintf(buf: cstring, size: csize, format: cstring): cint {.header: "<stdio.h>",
#                                  importc: "snprintf",
#                                  varargs, noSideEffect.}
#
#proc dtostrf(val: float, width: int8, prec: uint8, s: cstring): cstring {.importc.}
#
#proc sendGood(value: int32) =
#  var buffer: array[15, char]
#  discard snprintf(cast[cstring](buffer[0].addr), 15, "%ld", value)
#  Serial.send(cast[cstring](buffer[0].addr))
#  Serial.send "\c\n"
#
#proc sendGood(value: float32) =
#  var buffer: array[15, char]
#  discard dtostrf(value, 6, 2, cast[cstring](buffer[0].addr))
#  Serial.send(cast[cstring](buffer[0].addr))
#  Serial.send "\c\n"

while true:
  sensor.start(wait = false)
  delayMs(1000)
  sensor.readRaw(temperature, humidity, pressure)
  var tfine: int32
  compensateTemp(sensor.digT1, sensor.digT2, sensor.digT3, tfine, temperature)
  #sensor.readReal(temperature, humidity, pressure)
  #sendGood temperature
  #sendGood humidity
  #sendGood pressure
  if temperature < 3000: # Temperature less than 30 degrees
    Led.low()
  else:
    Led.high()
  delayMs(1000)

