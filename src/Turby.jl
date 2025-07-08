module Turby

using PyCall

export LuxSensor, Gain, gainlow, gainmedium, gainhigh, gainmax
export IntegrationTime, it100, it200, it300, it400, it500, it600
export setgain!, setintegrationtime!, visible

"""
```julia
LuxSensor()
```
Connect to a tsl2591 lux sensor via Blinka. On linux systems the following
commands should be executed in the system shell before attempting to connect:
- `sudo rmmod hid_mcp2221`:
  Remove the built-in driver for the mcp2221 chip
- `export BLINKA_MCP2221=1`:
  Tell Blinka what is connected to the computer (the MCP2221 is our usb adapter)
"""
struct LuxSensor
    adafruit
    sensor
    function LuxSensor()
        #python dependencies
        board = pyimport("board")
        adafruit_tsl2591 = pyimport("adafruit_tsl2591")
        i2c = board.I2C()
        new(adafruit_tsl2591,adafruit_tsl2591.TSL2591(i2c))
    end
end

"""
Possible gain values for a tsl2591 Lux sensor. Possible values are:
- `gainlow`
- `gainmedium`
- `gainhigh`
- `gainmax`
"""
@enum Gain begin
    #values taken from the python API
    gainlow
    gainmedium
    gainhigh
    gainmax
end

"""
Possible integrationtimes for a tsl2591 Lux sensor. Possible values are:
- `it100`
- `it200`
- `it300`
- `it400`
- `it500`
- `it600`
"""
@enum IntegrationTime begin
    #values taken from the python API
    it100
    it200
    it300
    it400
    it500
    it600
end

"""
```julia
setgain!(ls,gain)
```
Set the gain on the lux sensor `ls`. `gain` must be a member
of the `Gain` enum.
"""
function setgain!(ls::LuxSensor,gain::Gain)
    if gain == gainlow
        ls.sensor.gain = ls.adafruit.GAIN_LOW
    elseif gain == gainmedium
        ls.sensor.gain = ls.adafruit.GAIN_MED
    elseif gain == gainhigh
        ls.sensor.gain = ls.adafruit.GAIN_HIGH
    elseif gain == gainmax
        ls.sensor.gain = ls.adafruit.GAIN_MAX
    else
        error("this should be impossible")
    end
    return nothing
end

"""
```julia
setintegrationtime!(ls,it)
```
Set the integration time on the lux sensor `ls`. `it` must be a member
of the `IntegrationTime` enum.
"""
function setintegrationtime!(ls::LuxSensor,it::IntegrationTime)
    if it == it100
        ls.sensor.integration_time = ls.adafruit.INTEGRATIONTIME_100MS
    elseif it == it200
        ls.sensor.integration_time = ls.adafruit.INTEGRATIONTIME_200MS
    elseif it == it300
        ls.sensor.integration_time = ls.adafruit.INTEGRATIONTIME_300MS
    elseif it == it400
        ls.sensor.integration_time = ls.adafruit.INTEGRATIONTIME_400MS
    elseif it == it500
        ls.sensor.integration_time = ls.adafruit.INTEGRATIONTIME_500MS
    elseif it == it600
        ls.sensor.integration_time = ls.adafruit.INTEGRATIONTIME_600MS
    else
        error("should be impossible")
    end

    return nothing
end

"""
```julia
visible(ls)
```
Sample the intensity of the visible spectrum using the lux sensor `ls`
"""
function visible(ls::LuxSensor)
    ls.sensor.visible
end

end # module Turby
