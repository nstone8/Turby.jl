module Turby

using BlinkaBoards, TSL2591, PCA9685, DataFrames, CSVFiles, Dates, FileIO

export TurbyDevice, createconfig, dissociate, turbytest, loadposition, ejectposition, manualread

"""
```julia
createconfig([filename])
```
Create a configuration file, if `filename` is omitted `"config.jl"` will be used.

# Configuration parameters
- ledpin: GPIO pin for controlling the LED
- steppin: GPIO pin for actuating the stepper motor
- dirpin: GPIO pin controlling the stepper direction
- flipsteps: number of steps on the motor needed to flip the chamber
- tumbletime: time to wait between chamber flips
- sampletime: how long to tumble between turbidity measurements
- settletime: how long to allow the organoids to settle before turning on the lamp.
  This value should be greater than or equal to tumbletime
- lamptime: how long to wait between turning on the lamp and taking a turbidity measurment
- datafile: where to store the turbidity measurements, formatted as a path followed by a base name. the current date and time as well as `".csv"` will be appended
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
                        :steppin => 1,
                        :dirpin => 2,
                        :flipsteps => 100,
                        :tumbletime => 3,
                        :sampletime => 300,
                        :settletime => 28,
                        :lamptime => 2,
                        :datafile => "turbiditydata",
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
Stepper(step,dir)
```
Create a new `Stepper` by providing `DigitalIOPin`s for the direction and step signals
"""
struct Stepper
    step::DigitalIOPin
    dir::DigitalIOPin
end

"""
```julia
step(stepper,steps;delay=0.01,forward=true)
```
"""
function step(stepper::Stepper,steps::Int;delay=.01,forward=true)
    digitalwrite!(stepper.dir,forward)
    for _ in 1:steps
        digitalwrite(stepper.step,true)
        sleep(delay/2)
        digitalwrite(stepper.step,false)
        sleep(delay/2)
    end
end

"""
```julia
TurbyDevice(ledpinnum,steppinnum,dirpinnum)
```
"""
struct TurbyDevice
    ledpin::DigitalIOPin
    luxsensor::LuxSensor
    stepper::Stepper
    function TurbyDevice(ledpinnum,steppinnum,dirpinnum)
        #get a handle to a connected BlinkaBoard
        b = BlinkaBoard()
        #set up a digital io pin for output
        ledpin = DigitalIOPin(b,ledpinnum)
        steppin = DigitalIOPin(b,steppinnum)
        dirpin = DigitalIOPin(b,dirpinnum)
        stepper = Stepper(steppin,dirpin)
        #get our board's i2c bus
        bi2c = i2c(b)
        #set up our Lux Sensor
        luxsensor = LuxSensor(bi2c)
        new(ledpin,luxsensor,stepper)
    end
end

"""
```julia
flipchamber(td,forward,config)
```
Flip the chamber. Flip forward if `forward` is true otherwise flip backwards
"""
function flipchamber(td::TurbyDevice,forward::Bool,config::Dict)
    step(td.stepper,config[:flipsteps];forward)
end

"""
```julia
dissociate(configdict,[channel])
dissociate(configpath,[channel])
dissociate([channel])
```
Start a cycle of dissociation using the provided configuration parameters. If the configuration
is not provided it will be read from `"config.jl"`. If `channel` is provided, `(time_ms,turbidity)` values
will be written to this channel during the dissociation, closing this `Channel` will kill the
dissociation.
"""
function dissociate end

dissociate(channel=nothing) = dissociate("config.jl",channel)

function dissociate(configpath::AbstractString,channel=nothing)
    cdict = include(configpath)
    dissociate(cdict,channel)
end

#helper for constructing a TurbyDevice from config
function mkturby(;config...)
    td = TurbyDevice(config[:ledpin],config[:steppin],config[:dirpin])
    setgain!(td.luxsensor,config[:gain])
    setintegrationtime!(td.luxsensor,config[:integrationtime])
    return td
end

dissociate(config::Dict) = dissociate(config,nothing)

function dissociate(config::Dict,channel::Union{Channel,Nothing})
    #create our TurbyDevice
    td = mkturby(;config...)
    #number of times to tumble between samples
    numtumble = ceil(Int,config[:sampletime]/config[:tumbletime])
    #numtumble must be even so we take the measurement with the vial correctly oriented
    numtumble = iseven(numtumble) ? numtumble : numtumble + 1
    #create vectors to hold our data
    tsample = Number[]
    intensity = Number[]
    #little helper function to turn these vectors into a dataframe
    mkframe() = DataFrame(:time_ms => tsample,:intensity => intensity)
    #start the dissociation
    goingforward = !config[:endforward]
    tstart = now()
    datafile = config[:datafile] * Dates.format(tstart,dateformat"Y-m-d-HHMMSS") * ".csv"
    #flip to the read position
    flipchamber(td,config[:endforward],config)
    #once we're tumbling, we will have been in the read position for
    #:tumbletime at the top of this loop
    sleep(config[:tumbletime])
    #go until stopcondition returns true
    while true #implement stop condition here
        #time to take a measurement
        #allow the organoids to settle
        sleep(config[:settletime]-config[:tumbletime])
        #turn on the lamp
        digitalwrite!(td.ledpin,true)
        #wait for a bit
        sleep(config[:lamptime])
        #take the measurement
        thistime_ms::Millisecond = now()-tstart
        thistime = Dates.value(thistime_ms)
        push!(tsample,thistime)
        thismeasurement = visible(td.luxsensor)
        push!(intensity,thismeasurement)
        if !isnothing(channel)
            put!(channel,(thistime,thismeasurement))
        end
        #turn off the lamp and show the data
        digitalwrite!(td.ledpin,false)
        frame = mkframe()
        show(frame)
        println()
        save(datafile,frame)
        #tumble until next measurement
        for _ in 1:numtumble
            #test if we should stop
            if (!isnothing(channel) && !isopen(channel))
                return mkframe()
            end
            flipchamber(td,goingforward,config)
            goingforward = !goingforward
            sleep(config[:tumbletime])
        end
    end
    return mkframe()
end

"""
```julia
turbytest(rotations,configdict)
turbytest(rotations,configpath)
turbytest(rotations=3)
```
Test the device by driving forwards and backwards while blinking the light.
"""
function turbytest end

turbytest() = turbytest(3)

turbytest(rotations::Number) = turbytest(rotations,"config.jl")

function turbytest(rotations::Number,configpath::AbstractString)
    cdict = include(configpath)
    turbytest(rotations,cdict)
end

function turbytest(rotations::Number,config::Dict)
    td = mkturby(;config...)
    goingforward = !config[:endforward]
    #go forever
    for _ in 1:(2*rotations)
        flipchamber(td,goingforward,config)
        digitalwrite!(td.ledpin,goingforward)
        goingforward = !goingforward
        sleep(config[:tumbletime])
        @show visible(td.luxsensor)
    end
    #end in load position with the light off
    loadposition(config)
    digitalwrite!(td.ledpin,false)
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
ejectposition(configdict)
ejectposition(configpath)
ejectposition()
```
Move the chamber to the eject position
"""
function ejectposition end

ejectposition() = ejectposition("config.jl")

function ejectposition(configpath::AbstractString)
    cdict = include(configpath)
    ejectposition(cdict)
end

function ejectposition(config)
    td = mkturby(;config...)
    flipchamber(td,config[:endforward],config)
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
