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
//  right: current value of right servo
function setModel(model) {
    if ("left" in model) robotModel.left = model.left;
    if ("right" in model) robotModel.right = model.right;
}
// updateRobotModel handler
device.on("updateRobotModel", setModel);

// Sends message to the device to update servos
// -1.0 <= left <= 1.0
// -1.0 <= right <= 1.0
// id is an optional token to identify the request
function setServos(left, right, id = null) {
    device.send("setServos", {
        id = id,
        state = {
            left = left,
            right = right
        }
    });
}

// Handler for when we get a response back from setSerovs
// data should have:
//  id - the id we passed in the original request
//  state.left - the current value of the left servo
//  state.right - the current value of the right servo
device.on("setServosResp", function(data) {
    setModel(data.state);
    // any additional code required for once we get the response back
    // ...
});

