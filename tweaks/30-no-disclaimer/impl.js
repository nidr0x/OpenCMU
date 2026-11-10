/* opencmu:no-disclaimer
 * Acknowledge the disclaimer without a tap. Called as the Disclaimer
 * template's displayedFunction, so it runs when the template is shown.
 */
systemApp.prototype._noMoreDisclaimer = function () {
    framework.sendEventToMmui("system", "DisposeIntroVideo");
    framework.sendEventToMmui("common", "Global.Yes");
    framework.sendEventToMmui("system", "NotifyDisclaimerEnd");
};
