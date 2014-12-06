/********************** LIBRARY CODE **********************/
// Copyright (c) 2013 Electric Imp
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

// Twitter Keys
const API_KEY = "";
const API_SECRET = "";
const AUTH_TOKEN = "";
const TOKEN_SECRET = "";


// hashtag we're tracking
const HASHTAG = "#jazctrl"

class Twitter {
    // OAuth
    _consumerKey = null;
    _consumerSecret = null;
    _accessToken = null;
    _accessSecret = null;
    
    // URLs
    streamUrl = "https://stream.twitter.com/1.1/";
    tweetUrl = "https://api.twitter.com/1.1/statuses/update.json";
    
    // Streaming
    streamingRequest = null;
    _reconnectTimeout = null;
    _buffer = null;

    
    constructor (consumerKey, consumerSecret, accessToken, accessSecret) {
        this._consumerKey = consumerKey;
        this._consumerSecret = consumerSecret;
        this._accessToken = accessToken;
        this._accessSecret = accessSecret;
        
        this._reconnectTimeout = 60;
        this._buffer = "";
    }
    
    /***************************************************************************
     * function: Tweet
     *   Posts a tweet to the user's timeline
     * 
     * Params:
     *   status - the tweet
     *   cb - an optional callback
     * 
     * Return:
     *   bool indicating whether the tweet was successful(if no cb was supplied)
     *   nothing(if a callback was supplied)
     **************************************************************************/
    function tweet(status, cb = null) {
        local headers = { };
        
        local request = _oAuth1Request(tweetUrl, headers, { "status": status} );
        if (cb == null) {
            local response = request.sendsync();
            if (response && response.statuscode != 200) {
                server.log(format("Error updating_status tweet. HTTP Status Code %i:\r\n%s", response.statuscode, response.body));
                return false;
            } else {
                return true;
            }
        } else {
            request.sendasync(cb);
        }
    }
    
    /***************************************************************************
     * function: Stream
     *   Opens a connection to twitter's streaming API
     * 
     * Params:
     *   searchTerms - what we're searching for
     *   onTweet - callback function that executes whenever there is data
     *   onError - callback function that executes whenever there is an error
     **************************************************************************/
    function stream(searchTerms, onTweet, onError = null) {
        server.log("Opening stream for: " + searchTerms);
        // Set default error handler
        if (onError == null) onError = _defaultErrorHandler.bindenv(this);
        
        local method = "statuses/filter.json"
        local headers = { };
        local post = { track = searchTerms };
        local request = _oAuth1Request(streamUrl + method, headers, post);
        
        
        this.streamingRequest = request.sendasync(
            
            function(resp) {
                // connection timeout
                server.log("Stream Closed (" + resp.statuscode + ": " + resp.body +")");
                // if we have autoreconnect set
                if (resp.statuscode == 28 || resp.statuscode == 200) {
                    stream(searchTerms, onTweet, onError);
                } else if (resp.statuscode == 420) {
                    imp.wakeup(_reconnectTimeout, function() { stream(searchTerms, onTweet, onError); }.bindenv(this));
                    _reconnectTimeout *= 2;
                }
            }.bindenv(this),
            
            function(body) {
                 try {
                    if (body.len() == 2) {
                        _reconnectTimeout = 60;
                        _buffer = "";
                        return;
                    }
                    
                    local data = null;
                    try {
                        data = http.jsondecode(body);
                    } catch(ex) {
                        _buffer += body;
                        try {
                            data = http.jsondecode(_buffer);
                        } catch (ex) {
                            return;
                        }
                    }
                    if (data == null) return;

                    // if it's an error
                    if ("errors" in data) {
                        server.log("Got an error");
                        onError(data.errors);
                        return;
                    } 
                    else {
                        if (_looksLikeATweet(data)) {
                            onTweet(data);
                            return;
                        }
                    }
                } catch(ex) {
                    // if an error occured, invoke error handler
                    onError([{ message = "Squirrel Error - " + ex, code = -1 }]);
                }
            }.bindenv(this)
        
        );
    }
    
    /***** Private Function - Do Not Call *****/
    function _encode(str) {
        return http.urlencode({ s = str }).slice(2);
    }

    function _oAuth1Request(postUrl, headers, data) {
        local time = time();
        local nonce = time;
 
        local parm_string = http.urlencode({ oauth_consumer_key = _consumerKey });
        parm_string += "&" + http.urlencode({ oauth_nonce = nonce });
        parm_string += "&" + http.urlencode({ oauth_signature_method = "HMAC-SHA1" });
        parm_string += "&" + http.urlencode({ oauth_timestamp = time });
        parm_string += "&" + http.urlencode({ oauth_token = _accessToken });
        parm_string += "&" + http.urlencode({ oauth_version = "1.0" });
        parm_string += "&" + http.urlencode(data);
        
        local signature_string = "POST&" + _encode(postUrl) + "&" + _encode(parm_string);
        
        local key = format("%s&%s", _encode(_consumerSecret), _encode(_accessSecret));
        local sha1 = _encode(http.base64encode(http.hash.hmacsha1(signature_string, key)));
        
        local auth_header = "oauth_consumer_key=\""+_consumerKey+"\", ";
        auth_header += "oauth_nonce=\""+nonce+"\", ";
        auth_header += "oauth_signature=\""+sha1+"\", ";
        auth_header += "oauth_signature_method=\""+"HMAC-SHA1"+"\", ";
        auth_header += "oauth_timestamp=\""+time+"\", ";
        auth_header += "oauth_token=\""+_accessToken+"\", ";
        auth_header += "oauth_version=\"1.0\"";
        
        local headers = { 
            "Authorization": "OAuth " + auth_header
        };
        
        local url = postUrl + "?" + http.urlencode(data);
        local request = http.post(url, headers, "");
        return request;
    }
    
    function _looksLikeATweet(data) {
        return (
            "created_at" in data &&
            "id" in data &&
            "text" in data &&
            "user" in data
        );
    }
    
    function _defaultErrorHandler(errors) {
        foreach(error in errors) {
            server.log("ERROR " + error.code + ": " + error.message);
        }
    }

}

/******************** APPLICATION CODE ********************/
// Setup Twitter:
twitter <- Twitter(API_KEY, API_SECRET, AUTH_TOKEN, TOKEN_SECRET);

// Help message for twitter
helpMessage <- "SumoControl docs: " + http.agenturl();

// Sends a tweet to a particular user
function replyToTweet(userName, message) {
    local tweetString = format("@%s - %s (ts=%i)", userName, message, time());
    
    if (tweetString.len() > 140) {
        server.log("Trimming tweet: " + tweetString)
        tweetString = tweetString.slice(0, 139);
        server.log("New tweet: " + tweetString)
    }
    server.log(tweetString);
    twitter.tweet(tweetString);
}

// Robot Model and Controller
robotModel <- {
    left = null,
    right = null,
    
    toString = function() {
        return http.jsonencode({ left = left, right = right });
    },

    setModel = function(model) {
        if ("left" in model) robotModel.left = model.left;
        if ("right" in model) robotModel.right = model.right;
    }

};

robotController <- {
    commands = {
        r = { left = 1, right = 1 },
        l = { left = -1, right = -1 },
        f = { left = -1, right = 1 },
        b = { left = 1, right = -1 },
        p = { left = 0, right = 0 }
    },

    commandQueue = [],  // queue of upcoming commands
    lastId = null,    // the id to send a command
    timer = null,       // stores pointer to callback after command is done
    
    // executes the first command in the queue, and schedules the next command
    executeNextCommand = function() {
        // if there's a command
        if (commandQueue.len() > 0) {
            // grab the first command in the queue
            local cmd = commandQueue.remove(0);
            lastId = cmd.id;
            
            // send it to the device
            local data = { id = cmd.id, state = { left = cmd.left, right = cmd.right } };
            device.send("setServos", data);
            
            // schedule the next command to execute
            timer = imp.wakeup(cmd.t, executeNextCommand.bindenv(this));
        } else {
            // if there's no other commands, stop the robot and clear timer
            stop(lastId);
        }
    },

    // adds a new command to the queue
    pushCommand = function(user, left, right, t) {
        // push the command
        commandQueue.push({ id = user, left = left, right = right, t = t });
        
        // if we're not currently executing a command, execute it immediatly
        if (timer == null) {
            executeNextCommand();
        }
    },
  
    // hard stop
    stop = function(id) {
        // clear the timer if it exists
        if (timer != null) {
            imp.cancelwakeup(timer);
            timer = null;
        }

        local data = { id = id, state = { left = 0, right = 0 } };
        device.send("setServos", data);
    }
}

// Device Handlers
device.on("updateRobotModel", robotModel.setModel);
// Handler for when we recieve and response from our setServos message
// id is the twitter user who sent the command
device.on("setServosResp", function(data) {
    robotModel.setModel(data.state);
    //replyToTweet(data.id, "Set #SumoBot's servos to " + robotModel.toString());
});

// onTweet Callback
twitter.stream(HASHTAG, function(tweetData) {
    local user = tweetData.user.screen_name;    // pull out the username
    local tweet = tweetData.text.tolower();     // pull out the tweet text
    
    // log the tweet
    server.log("Got a tweet: @" + user + ": " + tweet);
    
    // break the tweet up into parts
    local parts = split(tweet, " ");

    // temporary command queue - if we dont run into errors, we will execute these    
    local commandQueue = [];
    local totalCommandTime = 0.0;
    
    foreach(part in parts) {
        // ignore the #sumocontrol part
        if (part == HASHTAG) continue;
        
        // if they asked for help, send help message and exit immediatly
        if (part == "help") {
            replyToTweet(user, helpMessage);
            return;
        }
        
        // if they sent a stop, send a stop command and exit immediatly
        if (part == "stop") {
            robotController.stop(user);
            return;
        }
        
        // grab the first character of the command (command identifier)
        local cmd = part.slice(0,1);

        // if we don't know the command, send back an error message and return immediatly
        if (!(cmd in robotController.commands)) {
            replyToTweet(user, "Unknown command '" + part + "' - " + helpMessage);
            return;
        } else {
            try {
                // if it is a known command, try to get the time
                local commandTime = part.slice(1, part.len()).tofloat();
                totalCommandTime += commandTime;
                
                // grab the left/right params for the servo, then queue the command
                local params = robotController.commands[cmd];
                robotController.pushCommand(user, params.left, params.right, commandTime);
            } catch(ex) {
                server.log(ex);
                // if there was an error, tweet back error and exit
                replyToTweet(user, "Bad parameter in command '" + part + "' - " + helpMessage);
                return;
            }
        }
    }
    
    //replyToTweet(user, format("Executing %i #SumoBot commands over %.2f seconds!", commandQueue.len(), totalCommandTime));
    // if we've made it this, we have zero or more commands to queue
    foreach(cmd in commandQueue) {
        // execute the commands (push onto command stack)
        robotController.commands[cmd.c](cmd.u, cmd.t)
    }
});

// HTTP Server to serve up help page
http.onrequest(function(req, resp) {
    resp.send(200, @"
        <html>
            <head>
                <title>SumoBot Help Page</title>
            </head>
            <body>
                <h1>Build your own TwitterSumoBot</h1>
                <p>All the code required for this project can be found <a href='https://github.com/beardedinventor/SumoBot/tree/master/TwitterSumoBot'>here</a>!
                <h1>Hash Tag</h1>
                <p>Use <strong>" + HASHTAG + @"</strong> to indicate you are sending commands to a SumoBot.</p>
                
                <h1>Commands:</h1>
                <p>Any of the commands can be chained together (with spaces between them) except 'help' and 'stop' - see the <strong>Examples</strong> section below for more information.</p>
                <ul>
                    <li><strong>help</strong>: Returns SumoBot's help menu</li>
                    <li><strong>stop</strong>: Stops SumoBot and clears all queued commands</li>
                    <li><strong>L{seconds}</strong>: Turns SumoBot left for the specified period of time</li>
                    <li><strong>R{seconds}</strong>: Turns SumoBot right for the specified period of time</li>
                    <li><strong>F{seconds}</strong>: Moves SumoBot forwards for the specified period of time</li>
                    <li><strong>B{seconds}</strong>: Moves SumoBot backwards for the specified period of time</li>
                    <li><strong>P{seconds}</strong>: Stops the SumoBot for the specified period of time</li>
                </ul>
                <h1>Example:</h1>
                <p>The following example uses the #sumocontrol hashtag.. make sure you use the above hashtag for your robot!</p>
                <blockquote class='twitter-tweet' data-partner='tweetdeck'><p><a href='https://twitter.com/hashtag/sumocontrol?src=hash'>#sumocontrol</a> F5 L0.5 F2 P1 B5.0</p>&mdash; Matt Haines (@BeardedInventor) <a href='https://twitter.com/BeardedInventor/status/540282757272727553'>December 3, 2014</a></blockquote><script async src='//platform.twitter.com/widgets.js' charset='utf-8'></script>
                <p>The above tweet will (in sequential order):
                    <ol>
                        <li>Move SumoBot <strong>F</strong>orwards for 5 seconds</li>
                        <li>Turn SumoBot <strong>L</strong>eft for 0.5 seconds</li>
                        <li>Move SumoBot <strong>F</strong>orwards for 2 seconds</li>
                        <li><strong>P</strong>ause for 1 second</li>
                        <li>Move SumoBot <strong>B</strong>ackwards for 5 seconds</li>
                    </ol>
                </p>
            </body>
        </html>
    ");
});
