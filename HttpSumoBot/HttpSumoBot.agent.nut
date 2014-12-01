// Manages incoming asynchronous requests
class RequestManager {
    _openRequests = null;
    _openRequestKey = null;
    
    _timeout = null;
    _maxRequests = null;
    
    constructor(timeout = 5, maxRequests = 3) {
        // set values
        _timeout = timeout;
        _maxRequests = maxRequests;
        
        // set values
        _openRequests = {};
        _openRequestKey = 0;
        
        // start the watchdog
        _requestWatchdog();
    }
    
    function push(req, resp) {
        // if we have the max number of requests open
        if (_openRequests.len() >= _maxRequests) {
            _closeOldestRequest();
        }
        
        // find next available key
        while(_openRequestKey in _openRequests) {
            _openRequestKey = ((_openRequestKey + 1) % 32767);
        }
        
        // add rewquest info to table with the available key we found
        _openRequests[_openRequestKey] <- {
            ts = time(),
            req = req,
            resp = resp
        };
    
        return _openRequestKey;
    }

    function getRequest(key) {
        // return the request if it exists
        if (key in _openRequests) {
            return _openRequests[key];
        }
        
        // return null if not found
        return null
    }

    function sendResponse(key, code, body) {
        local request = getRequest(key);
        if (request == null) return;

        request.resp.send(code, body);
        delete _openRequests[key];
    }

    /********** PRIVATE METHODS **********/
    function _closeOldestRequest() {
        local oldestRequestKey = null;
        
        // loop through and find oldest key
        foreach(k,v in _openRequests) {
            if (oldestRequestKey == null || _openRequests[k].ts < _openRequests[oldestRequestKey].ts) {
                oldestRequestKey = k;
            }
        }
        _timeoutRequest(oldestRequestKey);    
    }
    
    function _timeoutRequest(key) {
        sendResponse(key, 408, "DEVICE TIMEOUT");
    }
    
    function _requestWatchdog() {
        // run watchdog every second
        imp.wakeup(1, _requestWatchdog.bindenv(this));
        
        local t = time();
        foreach(k,v in _openRequests) {
            if (t - _openRequests[k].ts >= _timeout) {
                sendResponse(k, 408, "REQUEST TIMED OUT AFTER " + _timeout + " SECONDS");
            }
        }
    } 

}

// Agent's model of the device's attributes
robotModel <- {
    left = "UNKNOWN",
    right = "UNKNOWN",
    
    toString = function() {
        return http.jsonencode({ left = left, right = right });
    }
};

// updates the model
// model shoud contain:
//  left: current value of left servo
//  right: current value of right
function setModel(model) {
    if ("left" in model) robotModel.left = model.left;
    if ("right" in model) robotModel.right = model.right;
}
device.on("updateRobotModel", setModel);

// Sends message to the device to update servos
// -1.0 <= left <= 1.0
// -1.0 <= right <= 1.0
// id is an optional token to identify the request
function setServos(id, left, right) {
    device.send("setServos", {
        id = id,
        state = {
            left = left,
            right = right
        }
    });
}

// Handler for when we recieve and response from our setServos message
device.on("setServosResp", function(data) {
    setModel(data.state);
    requestManager.sendResponse(data.id, 200, robotModel.toString());
});

// The HTTP Handler
http.onrequest(function(req, resp) {
    try {
        local path = req.path.tolower();        // https://agent.electricimp.com/agentUrl{path}
        local method = req.method.tolower();    // GET, PUT, POST, etc
        
        local data = req.body;                  // body of request

        // try to automagically parse the body
        if ("content-type" in req.headers) {
            local contentType = req.headers["content-type"].tolower();
            
            if (contentType == "application/json") {
                data = http.jsondecode(req.body);
            } else if (contentType == "application/x-www-form-urlencoded") {
                data = http.urldecode(req.body);
            }
        }
        
        switch(path) {
            case "/":
                // test endpoint - always returns 200, OK
                resp.send(200, "OK");
                break;
            case "/state":
            case "/state/":
                // returns the current state
                resp.send(200, http.jsonencode(robotModel));
                break;
            case "/stop":
            case "/stop/":
                // Sets servos to (0,0) and returns servo values (should be 0,0)
                local id = requestManager.push(req, resp);
                setServos(id, 0,0);
                break;
            case "/set":
            case "/set/":
                // Sets servos to (left,right) and returns servo values (should be left,right)
                local left = null;
                local right = null;
                
                // Many ways to get left/right
                if (data != null && "left" in data) {
                    left = data.left;
                } else if ("left" in req.query) {
                    left = req.query.left.tofloat();
                }
                
                if (data != null && "right" in data) {
                    right = data.right;
                } else if ("right" in req.query) {
                    right = req.query.right.tofloat();
                }
                
                local id = requestManager.push(req, resp);
                setServos(id, left, right);
                break;
            default: 
                // if a command is sent anywhere else, return 404
                resp.send(404, "Unknown");
                break;
        }
    } catch (ex) {
        // if there was an error, send back a 500
        resp.send(500, "Internal Agent Error: " + ex);
    }
});

