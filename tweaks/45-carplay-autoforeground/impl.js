/* opencmu:carplay-autoforeground
 * On the transition from "no session" to "session active", raise CarPlay the
 * same way the on-screen button does. Fires once per session and never while a
 * consent screen is up, so a phone that needs approval still gets its prompt.
 */
(function () {
    if (typeof carplayApp === "undefined" || !carplayApp.prototype ||
        carplayApp.prototype._opencmuAutoForeground) {
        return;
    }
    carplayApp.prototype._opencmuAutoForeground = true;

    var stock = carplayApp.prototype._SendCPSessionStateMsgHandler;
    if (typeof stock !== "function") {
        return;
    }

    var active = function (state) {
        return !!(state && state.state === true);
    };

    var hasDevice = function (state) {
        return !!(state && ((state.btMacAddress && state.btMacAddress.length) ||
                            (state.serialId && state.serialId.length)));
    };

    var contextId = function (ctrl) {
        var template = ctrl._currentContextTemplate;
        return (template && template.contextInfo) ? template.contextInfo.ctxtId : null;
    };

    carplayApp.prototype._SendCPSessionStateMsgHandler = function (msg) {
        var before = active(this._cachedCPSessionState);

        stock.apply(this, arguments);

        var state = this._cachedCPSessionState;

        if (!active(state)) {
            this._opencmuForegroundDone = false;
            return;
        }
        if (before || this._opencmuForegroundDone) {
            return;
        }
        if (!hasDevice(state)) {
            return;
        }

        var here = contextId(this);
        if (here === "CarPlayUI" || here === "NoteOnUseData" || here === "NoteOnUseDataWCP") {
            return;
        }

        this._opencmuForegroundDone = true;
        framework.sendEventToMmui(this.uiaId, "SelectActiveDevice");
        framework.sendEventToMmui("common", "Global.ClearReconnectDialog");
    };
})();
