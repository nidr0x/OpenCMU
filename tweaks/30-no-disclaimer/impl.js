/* opencmu:no-disclaimer
 * Acknowledge the disclaimer without a tap. Called from the Disclaimer
 * template's readyFunction, so it runs once the template is on screen.
 */
systemApp.prototype._noMoreDisclaimer = function () {
    framework.sendEventToMmui("system", "DisposeIntroVideo");
    framework.sendEventToMmui("common", "Global.Yes");
    framework.sendEventToMmui("system", "NotifyDisclaimerEnd");
};
