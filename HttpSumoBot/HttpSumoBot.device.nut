// Servo class - makes working with servos really simple
class Servo {
    
    _pin = null;
    _min = 0.0;
    _max = 1.0;
    
    constructor(pin, min = 0.0, max = 1.0, period=0.02, dutycycle=0.5) {
        _min = min;
        _max = max;

        _pin = pin;
        _pin.configure(PWM_OUT, period, dutycycle);
    }
    
    // Sets the minimum and maximum of the output scale. Both should be between 0.0 and 1.0.
    function scale(min, max) {
        _min = min;
        _max = max;
    }
    
    // val: 0.0 <= val <= 1.0
    function write(val) {
        if (val <= 0.0) val = 0.0;
        else if (val >= 1.0) val = 1.0;
        local last_write = val.tofloat();

        local f = 0.0 + _min + ( last_write.tofloat() * (_max - _min));
        return _pin.write(f);
    }
}

// SumoBot class - makes working with a SumoBot really simple! 
class SumoBot {
    _leftServo = null;
    _rightServo = null;
    
    _left = null;
    _right = null;
    
    constructor(leftServo, rightServo) {
        _leftServo = leftServo;
        _rightServo = rightServo;
        
        stop();
    }
    
    // Sets left = right = 0.0;
    function stop() {
        setServos(0,0);
    }
    
    // leftSpeed:   -1.0 < x < 1.0
    // rightSpeed:  -1.0 < x < 1.0
    function setServos(leftSpeed, rightSpeed) {
        // clamp values and store
        if (leftSpeed != null) {
            if (leftSpeed < -1) leftSpeed = -1.0;
            if (leftSpeed > 1) leftSpeed = 1.0;
            _left = 0.5 + 0.5 * leftSpeed;
        }
        if (rightSpeed != null) {
            if (rightSpeed < -1) rightSpeed = -1.0;
            if (rightSpeed > 1) rightSpeed = 1.0;
            _right = 0.5 + 0.5 * rightSpeed;
        }
        
        // write values to servos
        _leftServo.write(_left);
        _rightServo.write(_right);
    }
    
    // return { left: x, right: y }
    // with values [ -1.0 < x,y < 1.0 ]
    function getState() {
        return {
            left = _left * 2.0 - 1.0,
            right = _right * 2.0 - 1.0
        }
    }
}

// Create SumoBot object
leftWheel <- Servo(hardware.pin5, 0.04, 0.11)
rightWheel <- Servo(hardware.pin7, 0.04, 0.11)
robot <- SumoBot(leftWheel, rightWheel);

agent.send("updateRobotModel", robot.getState());

agent.on("setServos", function(data) {
    local left = null;
    local right = null;
    
    if ("state" in data && "left" in data.state) left = data.state.left;
    if ("state" in data && "right" in data.state) right = data.state.right;

    // set servos, and send resp
    robot.setServos(left, right);
    agent.send("setServosResp", { id = data.id, state = robot.getState() });
});

