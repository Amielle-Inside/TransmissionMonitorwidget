function testConnection(host, port, user, pass, rpcPath) {
    console.log("testConnection called with:", host, port, user, "***", rpcPath);
    
    var url = "http://" + host + ":" + port + rpcPath;
    console.log("Test URL:", url);
    
    var xhr = new XMLHttpRequest();
    xhr.open("POST", url, false); // synchronous for config dialog
    xhr.setRequestHeader("Content-Type", "application/json");
    var auth = Qt.btoa(user + ":" + pass);
    xhr.setRequestHeader("Authorization", "Basic " + auth);
    
    // Test with session-stats (lightweight call)
    var body = JSON.stringify({method: "session-stats", arguments: {}});
    xhr.send(body);
    
    if (xhr.status === 409) {
        // Get session ID and retry
        var sessionId = xhr.getResponseHeader("X-Transmission-Session-Id");
        console.log("Got session ID:", sessionId);
        xhr.open("POST", url, false);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.setRequestHeader("Authorization", "Basic " + auth);
        xhr.setRequestHeader("X-Transmission-Session-Id", sessionId);
        xhr.send(body);
    } else if (xhr.status === 200) {
        var sessionId = xhr.getResponseHeader("X-Transmission-Session-Id");
        console.log("Got session ID on first try:", sessionId);
    }
    
    console.log("Response status:", xhr.status);
    console.log("Response text:", xhr.responseText);
    
    if (xhr.status !== 200) {
        var errorMsg = "Connection failed: HTTP " + xhr.status;
        if (xhr.responseText) {
            errorMsg += " - " + xhr.responseText;
        }
        console.error("❌", errorMsg);
        return {success: false, error: errorMsg};
    }
    
    try {
        var response = JSON.parse(xhr.responseText);
        if (response.result !== "success") {
            var errorMsg = "RPC error: " + response.result;
            console.error("❌", errorMsg);
            return {success: false, error: errorMsg};
        }
        
        console.log("✅ Connection successful!");
        console.log("Session stats:", response.arguments);
        return {success: true, data: response.arguments};
    } catch (e) {
        var errorMsg = "Parse error: " + e.message;
        console.error("❌", errorMsg);
        return {success: false, error: errorMsg};
    }
}

// Also expose for plasmoid.runScript
function testConnectionScript() {
    return testConnection(
        plasmoid.configuration.trHost || "localhost",
        plasmoid.configuration.trPort || 9091,
        plasmoid.configuration.trUser || "Amielle",
        plasmoid.configuration.trPass || "NewsInside@15",
        plasmoid.configuration.trRpcPath || "/transmission/rpc"
    );
}