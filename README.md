SumoBot
=======
This repo is a collection of projects based around the [SumoBot Kit](http://sumobotkit.com/).

Files
=====

SumoBase.*.nut
--------------
These two files implement the SumoBot's base functionality - turning servo's on and off, and passing messages between the agent and device, and vica versa.

This code *needs* to be extended in order to be functional (as there is no means of communbicating with the agent).

HttpSumoBot
-----------
HttpSumoBot is a basic implementation of the SumoBot using a simple HTTPS interface. You can hit the following end points:

- **GET /** - Test endpoint, should always return "200, OK"
- **GET /state** - Returns the current values of the SumoBot's servos (between -1.0 and 1.0)
- **GET /stop** - Sets the servos to (0,0) and returns the current values of the SumoBot's servos (should be 0,0)
- **GET /set** - Sets the servos to the specified values. Values are specified with two query parameters - *left* and *right* (i.e. ``` /set?left=0.5&right=0.6```)
- **POST /set** - You can also set the servos using a post request and JSON packet containing the required values:
    ``` { "left": 0.5, "right": 0.6 } ```

TwitterSumoBot
--------------
TwitterSumoBot is an implementation of SumoBot that uses the Twitter Streaming API. Tweet "#sumocontrol help" for more information!

LICENSE
=======
This software is free and unencumbered and released into the public domain. More information can be found in the [LICENSE](LICENSE) file.
