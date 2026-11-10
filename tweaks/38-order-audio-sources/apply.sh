#!/bin/sh
# shellcheck disable=SC2154
target="$OPENCMU_ROOT/jci/gui/apps/system/js/systemApp.js"
[ -f "$target" ] || die "systemApp.js not found: $target"

order="${OPENCMU_AUDIO_ORDER:-}"
[ -n "$order" ] || die "set OPENCMU_AUDIO_ORDER to a comma-separated list of source IDs"
case "$order" in
  *[!A-Za-z0-9_,]*) die "order may contain only source IDs separated by commas" ;;
esac

# The IDs are the stock entertainment source IDs taken from the 74.00.324
# master list (systemApp.js, _initEntertainmentDataList). Anything else is a
# typo. TrafficInfo is the traffic-alert item, not an audio source, but it is
# part of the same visible list so ordering it is allowed.
_seen=","
for _id in $(printf '%s' "$order" | tr ',' ' '); do
  case $_id in
    USB_A|USB_B|BTAudio|FMRadio|AMRadio|AuxIn|TrafficInfo|DAB|SatRadio|XmAudio|AhaRadio|Pandora|Stitcher|CarPlay|CarPlayWifi|AndroidAuto|CD|DVD|TV) ;;
    *) die "unknown audio source ID: $_id (stock IDs: USB_A, USB_B, BTAudio, FMRadio, AMRadio, AuxIn, TrafficInfo, DAB, SatRadio, XmAudio, AhaRadio, Pandora, Stitcher, CarPlay, CarPlayWifi, AndroidAuto, CD, DVD, TV)" ;;
  esac
  case ,"$_seen" in
    *",$_id,"*) die "source ID repeated: $_id" ;;
  esac
  _seen="$_seen$_id,"
done

block="$target.opencmu-order.$$"
sed "s/__OPENCMU_AUDIO_ORDER__/$order/" "$dir/impl.js" > "$block" ||
  { rm -f "$block"; die "cannot prepare the wrapper block"; }
grep -q '__OPENCMU_AUDIO_ORDER__' "$block" && {
  rm -f "$block"
  die "placeholder not substituted"
}

append_once "$target" 'opencmu:order-audio-sources' "$block"
rm -f "$block"
log "audio source order applied: $order"
