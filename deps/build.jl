using Conda
Conda.pip_interop(true)
Conda.pip("install",["Adafruit-Blinka",
                     "adafruit-circuitpython-tsl2591",
                     "hidapi"])
