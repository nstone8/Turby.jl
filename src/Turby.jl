module Turby

using BlinkaBoards, TSL2591, PCA9685, PCA9548, DataFrames, CSVFiles, Dates, FileIO

export TurbyDevice, createconfig, dissociate, turbytest, loadposition, manualread

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
- gain: gain for the `LuxSensor`
- integrationtime: integration time for the `LuxSensor`
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
                        :tumbletime => 3,
                        :sampletime => 300,
                        :settletime => 28,
                        :lamptime => 2,
                        :datafile => "turbiditydata.csv",
                        :endforward => true,
                        :gain => gainmedium,
                        :integrationtime => it300
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
flipchamber(td,forward,config)
```
Flip the chamber. Flip forward if `forward` is true otherwise flip backwards
"""
function flipchamber(td::TurbyDevice,forward::Bool,config::Dict)
    throttle = forward ? config[:forwardspeed] : config[:reversespeed]
    throttlestop = forward ? config[:forwardstop] : config[:reversestop]
    setthrottle!(td.servo,config[:servochannel],throttle)
    sleep(config[:tflip])
    setthrottle!(td.servo,config[:servochannel],throttlestop)
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
function mkturby(;config...)
    td = TurbyDevice(config[:ledpin],config[:luxaddress],config[:servoaddress])
    setgain!(td.luxsensor,config[:gain])
    setintegrationtime!(td.luxsensor,config[:integrationtime])
    return td
end

function dissociate(config::Dict)
    #create our TurbyDevice
    td = mkturby(;config...)
    #number of times to tumble between samples
    numtumble = ceil(Int,config[:sampletime]/config[:tumbletime])
    #numtumble must be even so we take the measurement with the vial correctly oriented
    numtumble = iseven(numtumble) ? numtumble : numtumble + 1
    #create vectors to hold our data
    tsample = Millisecond[]
    intensity = Number[]
    #little helper function to turn these vectors into a dataframe
    mkframe() = DataFrame(:time_ms => Dates.value.(tsample),:intensity => intensity)
    #start the dissociation
    goingforward = !config[:endforward]
    tstart = now()
    #flip to the read position
    flipchamber(td,config[:endforward],config)
    #go until stopcondition returns true
    while true #implement stop condition here
        #time to take a measurement
        #allow the organoids to settle
        sleep(config[:settletime])
        #turn on the lamp
        digitalwrite!(td.ledpin,true)
        #wait for a bit
        sleep(config[:lamptime])
        #take the measurement
        push!(tsample,now()-tstart)
        push!(intensity,visible(td.luxsensor))
        #turn off the lamp and show the data
        digitalwrite!(td.ledpin,false)
        frame = mkframe()
        show(frame)
        println()
        save(config[:datafile],frame)
        #tumble until next measurement
        for _ in 1:numtumble
            flipchamber(td,goingforward,config)
            goingforward = !goingforward
            sleep(config[:tumbletime]-config[:tflip])
        end
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
        flipchamber(td,goingforward,config)
        digitalwrite!(td.ledpin,goingforward)
        goingforward = !goingforward
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
    flipchamber(td,!config[:endforward],config)
end

"""
```julia
manualread(datapath)
manualread(datapath,configpath)
manualread(datapath,config)
```
Take manual turbidity measurements.
"""
function manualread end

manualread(datapath) = manualread(datapath::AbstractString,"config.jl")

function manualread(datapath::AbstractString,configpath::AbstractString)
    cdict = include(configpath)
    manualread(datapath,cdict)
end

function manualread(datapath::AbstractString,config::Dict)
    #keep going until asked to stop
    td = mkturby(;config...)
    #go to load position
    flipchamber(td,!config[:endforward],config)
    samplenames = String[]
    intensities = Number[]
    #keep going until asked to stop
    while true
        println("Load sample and enter sample name. Leave blank to stop.")
        samplename = readline()
        if isempty(samplename)
            break
        end
        push!(samplenames,samplename)
        #go to 'read' position
        flipchamber(td,config[:endforward],config)
        digitalwrite!(td.ledpin,true)
        sleep(config[:lamptime])
        intensity = visible(td.luxsensor)
        push!(intensities,intensity)
        println("measured intensity: $intensity")
        digitalwrite!(td.ledpin,false)
        #go to load position
        flipchamber(td,!config[:endforward],config)
        println("remove lid and press enter to eject sample")
        readline()
        #go to 'read' position
        flipchamber(td,config[:endforward],config)
        sleep(5)
        #go to load position
        flipchamber(td,!config[:endforward],config)
    end
    data = DataFrame(sample = samplenames, intensity = intensities)
    save(datapath,data)
    return data
end

end # module Turby
