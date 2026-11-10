/* [opencmu:select-bt-audio-first] Selects Bluetooth audio once per boot.
 *
 * Wrap of the stock _StatusMenuBTAudioMsgHandler. The stock body runs first;
 * afterwards, when its message reports appStatus "Available" together with a
 * non-empty deviceName (the stock signal that a BT audio device connected),
 * the stock SelectBTAudio event the menu item itself would send
 * (_menuItemSelectCallback) is sent once. Later availability messages are
 * ignored, so a reconnect during a drive does not steal the active source.
 */
(function () {
    if (typeof systemApp === "undefined" || !systemApp.prototype) {
        return;
    }
    if (systemApp.prototype.opencmuBtAudioFirstWrapped) {
        return;
    }
    var stockHandler = systemApp.prototype._StatusMenuBTAudioMsgHandler;
    if (typeof stockHandler !== "function") {
        return;
    }
    var autoSelected = false;
    var wrapped = function (msg) {
        stockHandler.apply(this, arguments);
        try {
            if (autoSelected) {
                return;
            }
            var payload = msg && msg.params && msg.params.payload;
            if (!payload || payload.appStatus !== "Available") {
                return;
            }
            var deviceName = payload.deviceName;
            if (typeof deviceName !== "string" || deviceName.length === 0) {
                return;
            }
            autoSelected = true;
            framework.sendEventToMmui(this.uiaId, "SelectBTAudio");
        } catch (e) {
            if (typeof log !== "undefined" && log.debug) {
                log.debug("opencmu select-bt-audio-first: " + e);
            }
        }
    };
    systemApp.prototype.opencmuBtAudioFirstWrapped = true;
    systemApp.prototype._StatusMenuBTAudioMsgHandler = wrapped;
})();
