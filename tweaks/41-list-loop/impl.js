/* opencmu:list-loop
 * Wrap the rotary-knob handlers: at the last enabled row, "next" goes to the
 * first; at the first, "previous" goes to the last. Every other move is passed
 * to the stock handler untouched.
 */
(function () {
    var proto = window.List2Ctrl && List2Ctrl.prototype;
    if (!proto || proto._opencmuListLoop) {
        return;
    }
    proto._opencmuListLoop = true;

    proto._opencmuLoopStep = function (direction) {
        if (this._inListReorder || this._inLetterIndexMulticontroller) {
            return false;
        }
        if (typeof this.hasDataList === "function" && !this.hasDataList()) {
            return false;
        }
        if (!this.dataList || !this.dataList.itemCountKnown) {
            return false;
        }

        var count = this.dataList.itemCount;
        if (count <= 1) {
            return false;
        }

        var first = this._getNearestEnabledItemByDirection(-1, "down");
        var last = this._getNearestEnabledItemByDirection(count, "up");
        if (first === null || last === null || first === last) {
            return false;
        }

        var focused = this._getFocussedIndex();
        if (direction === "next" && focused === last) {
            this._scrollTo(0, 0);
            this._showFocus(first);
            this._scrollNature = "item";
            return true;
        }
        if (direction === "prev" && focused === first) {
            this._scrollTo(Math.max(count - this.properties.visibleItems, 0), 0);
            this._showFocus(last);
            this._scrollNature = "item";
            return true;
        }
        return false;
    };

    var hook = function (name, direction) {
        var stock = proto[name];
        if (typeof stock !== "function") {
            return;
        }
        proto[name] = function () {
            if (this._opencmuLoopStep(direction)) {
                return "consumed";
            }
            return stock.apply(this, arguments);
        };
    };

    hook("_handleMCCW", "next");
    hook("_handleMCDown", "next");
    hook("_handleMCCCW", "prev");
    hook("_handleMCUp", "prev");
})();
