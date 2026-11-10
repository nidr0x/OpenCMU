/* [opencmu:order-audio-sources] Reorders the entertainment source list.
 *
 * Wrap of the stock list builder: the stock function runs first, then the
 * preferred sources described below are moved to the front, in this order,
 * while the remaining entries keep their stock relative order. The stock
 * source IDs verified in the 74.00.324 master list: FMRadio, AMRadio, DAB,
 * SatRadio, XmAudio, AhaRadio, Pandora, Stitcher, BTAudio, CarPlayWifi,
 * CarPlay, AndroidAuto, USB_A, USB_B, CD, AuxIn, DVD, TV and TrafficInfo.
 * The wrapper never selects a source; it only orders the visible list.
 */
(function () {
    if (typeof systemApp === "undefined" || !systemApp.prototype) {
        return;
    }
    if (systemApp.prototype.opencmuAudioOrderWrapped) {
        return;
    }
    if (typeof systemApp.prototype._buildEntertainmentDataList !== "function") {
        return;
    }
    systemApp.prototype.opencmuAudioOrderWrapped = true;
    var preferredAudioSourceIds = "__OPENCMU_AUDIO_ORDER__".split(",");
    var buildDataList = systemApp.prototype._buildEntertainmentDataList;
    systemApp.prototype._buildEntertainmentDataList = function () {
        var dataList = buildDataList.apply(this, arguments);
        var remaining = dataList.items.slice(0);
        var ordered = [];
        var i, j;
        for (i = 0; i < preferredAudioSourceIds.length; i++) {
            for (j = 0; j < remaining.length; j++) {
                if (remaining[j] && remaining[j].appData &&
                    remaining[j].appData.audioSourceId === preferredAudioSourceIds[i]) {
                    ordered.push(remaining[j]);
                    remaining.splice(j, 1);
                    break;
                }
            }
        }
        dataList.items = ordered.concat(remaining);
        dataList.itemCount = dataList.items.length;
        return dataList;
    };
})();
