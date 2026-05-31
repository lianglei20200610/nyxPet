const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("webkit", {
  messageHandlers: {
    pet: {
      postMessage(payload) {
        ipcRenderer.send("pet-message", payload);
      }
    }
  }
});
