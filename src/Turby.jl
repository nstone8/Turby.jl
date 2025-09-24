module Turby

using BlinkaBoards, TSL2591, PCA9685, PCA9548, DataFrames, CSVFiles, Dates, FileIO

export measuretofile, TurbyDevice, createconfig, dissociate, turbytest, loadposition

"""
```julia
createconfig([filename])
```
Create a configuration file, if `filename` is omitted `"config.jl"` will be used.

# Configuration parameters
- ledpin: GPIO pin for controlling the LED
- luxaddress: i2c channel on the multiplexer connected to the `LuxSensor`
- servoaddress: i2c channel on the multiplexer connected to the `ServoDriver`
- servochannel: physical channel on the `ServoDriver` which is connected to the continuous servo
- forwardspeed: throttle command to drive the servo forward
- forwardstop: throttle command to hold the servo at the forward stop
- reversespeed: throttle command to drive the servo backwards
- reversestop: throttle command to hold the servo at the reverse stop
- tflip: time it takes the chamber to flip
- tumbletime: time to wait between chamber flips
- sampletime: how long to tumble between turbidity measurements
- settletime: how long to allow the organoids to settle before turning on the lamp
- lamptime: how long to wait between turning on the lamp and taking a turbidity measurment
- datafile: where to store the turbidity measurements
- endforward: true if driving forward puts the vial in the correct position to take a measurement
- stopcondition: NOT YET IMPLEMENTED
"""
function createconfig end

createconfig() = createconfig("config.jl")

function createconfig(filename::AbstractString)
    open(filename,"w") do io
        dictstr = """
                Dict(
                        :ledpin => 0,
                        :luxaddress => 0,
                        :servoaddress => 2,
                        :servochannel => 0,
                        :forwardspeed => .2,
                        :forwardstop => 0,
                        :reversestop => 0,
                        :tflip => 1,
                        :reversespeed => -.2,
                        :tumbletime => 5,
                        :sampletime => 180,
                        :settletime => 10,
                        :lamptime => 5,
                        :datafile => "turbiditydata.csv",
                        :endforward => true
                )
    """
        print(io,dictstr)
    end
end
    
"""
```julia
TurbyDevice(ledpinnum,luxaddress,servoaddress)
```
"""
struct TurbyDevice
    ledpin::DigitalIOPin
    luxsensor::LuxSensor
    servo
    function TurbyDevice(ledpinnum,luxaddress,servoaddress)
        #get a handle to a connected BlinkaBoard
        b = BlinkaBoard()
        #set up a digital io pin for output
        ledpin = DigitalIOPin(b,ledpinnum)
        #set up our i2c multiplexer
        multi = MultiI2C(i2c(b))
        #set up our Lux Sensor
        luxsensor = LuxSensor(multi[luxaddress])
        servo = ServoDriver(multi[servoaddress])
        new(ledpin,luxsensor,servo)
    end
end

"""
```julia
dissociate(configdict)
dissociate(configpath)
dissociate()
```
Start a cycle of dissociation using the provided configuration parameters. If the configuration
is not provided it will be read from `"config.jl"`
"""
function dissociate end

dissociate() = dissociate("config.jl")

function dissociate(configpath::AbstractString)
    cdict = include(configpath)
    dissociate(cdict)
end

#helper for constructing a TurbyDevice from config
mkturby(;config...) = TurbyDevice(config[:ledpin],config[:luxaddress],config[:servoaddress])

function dissociate(config::Dict)
    #create our TurbyDevice
    td = mkturby(;config...)
    #number of times to tumble between samples
    numtumble = ceil(Int,config[:sampletime]/config[:tumbletime])
    #numtumble must be even so we take the measurement with the vial correctly oriented
    numtumble = iseven(numtumble) ? numtumble : numtumble + 1
    #create vectors to hold our data
    tsample = DateTime[]
    intensity = Number[]
    #little helper function to turn these vectors into a dataframe
    mkframe() = DataFrame(:time => tsample,:intensity => intensity)
    #start the dissociation
    tstart = now()
    goingforward = !config[:endforward]
    #go until stopcondition returns true
    while true #implement stop condition here
        for _ in 1:numtumble
            throttle = goingforward ? config[:forwardspeed] : config[:reversespeed]
            throttlestop = goingforward ? config[:forwardstop] : config[:reversestop]
            goingforward = !goingforward
            setthrottle!(td.servo,config[:servochannel],throttle)
            sleep(config[:tflip])
            setthrottle!(td.servo,config[:servochannel],throttlestop)
            sleep(config[:tumbletime]-config[:tflip])
        end
        #time to take a measurement
        #allow the organoids to settle
        sleep(config[:settletime])
        #turn on the lamp
        digitalwrite!(td.ledpin,true)
        #wait for a bit
        sleep(config[:lamptime])
        #take the measurement
        push!(tsample,now())
        push!(intensity,visible(td.luxsensor))
        #turn off the lamp and show the data
        digitalwrite!(td.ledpin,false)
        frame = mkframe()
        show(frame)
        println()
        save(config[:datafile],frame)
    end
    return mkframe()
end

"""
```julia
turbytest(configdict)
turbytest(configpath)
turbytest()
```
Test the device by driving forwards and backwards while blinking the light
"""
function turbytest end

turbytest() = turbytest("config.jl")

function turbytest(configpath::AbstractString)
    cdict = include(configpath)
    turbytest(cdict)
end

function turbytest(config)
    td = mkturby(;config...)
    goingforward = !config[:endforward]
    #go forever
    while true
        throttle = goingforward ? config[:forwardspeed] : config[:reversespeed]
        throttlestop = goingforward ? config[:forwardstop] : config[:reversestop]
        goingforward = !goingforward
        setthrottle!(td.servo,config[:servochannel],throttle)
        digitalwrite!(td.ledpin,goingforward)
        sleep(config[:tflip])
        setthrottle!(td.servo,config[:servochannel],throttlestop)
        digitalwrite!(td.ledpin,!goingforward)
        sleep(config[:tumbletime]-config[:tflip])
        @show visible(td.luxsensor)
    end
end

"""
```julia
loadposition(configdict)
loadposition(configpath)
loadposition()
```
Move the chamber to the load position
"""
function loadposition end

loadposition() = loadposition("config.jl")

function loadposition(configpath::AbstractString)
    cdict = include(configpath)
    loadposition(cdict)
end

function loadposition(config)
    td = mkturby(;config...)
    (throttle,throttlestop) = config[:endforward] ?
        (config[:reversespeed],config[:reversestop]) :
        (config[:forwardspeed],config[:forwardstop])
    setthrottle!(td.servo,config[:servochannel],throttle)
    sleep(config[:tflip])
    setthrottle!(td.servo,config[:servochannel],throttlestop)
end

"""
```julia
measuretofile(ls,filename;gain=gainmedium,it=it200,nmeasurements=5)
```
Take visible intensity measurements from the `LuxSensor` `ls` and write the results to
a plaintext file at `filename`. Keyword arguments allow for the adjustment of the sensor
gain, integration time and the number of measurements to be taken.
"""
function measuretofile(ls::LuxSensor,filename;gain=gainmedium,it=it200,nmeasurements=5)
    @assert !isfile(filename) "$filename already exists"
    setgain!(ls,gain)
    setintegrationtime!(ls,it)
    sleep(1) #allow changes to sink in
    #take 5 measurements and save them to a file
    measurements = map(1:nmeasurements) do _
        v = visible(ls)
        println(v)
        sleep(1)
        return v
    end

    open(filename,"w") do io
        for m in measurements
            println(io,m)
        end
    end
end

end # module Turby
