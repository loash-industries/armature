// Shim for the `ws` npm package in browser builds.
// The relay-sdk imports `ws` as a default import and uses it as the WebSocket
// constructor. In the browser we re-export the native global — the relay-sdk's
// socket code uses the HTML5 EventTarget API so it works with both.
export default WebSocket
