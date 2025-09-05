
# Determine the conversion factor for the circle on the map
# The leaflet parameter wants input in meters
if [[ -n "$SOCKETCONFIG" ]]; then
  case "$(grep "^distanceunit=" "$SOCKETCONFIG" |sed "s/distanceunit=//g")" in
    nauticalmile)
    # 1 NM is 1852 meters
    TO_METER=1852
    ;;
    kilometer)
    # 1 km is 1000 meters
    TO_METER=1000
    ;;
    mile)
    # 1 mi is 1609 meters
    TO_METER=1609
    ;;
    meter)
    # 1 meter is 1 meters
    TO_METER=1
  esac
fi

# -----------------------------------------------------------------------------------
# Now create the heatmap data

{ printf -v "var addressPoints = [\n"
  for i in "${!records[@]}"; do
    if [[ "${i:0:7}" == "heatmap" ]]; then
      printf "[ %s,%s ],\n" "${i:7}" "${records[$i]}"
    fi
  done
  printf "];\n"
} > "$OUTFILEDIR/planeheatdata-$TODAY.js"

# And return the heatmap HTML code to be inserted

DISTMTS="$(awk "BEGIN{print int($DIST * $TO_METER)}")"
echo "<div id=\"map\" style=\"width: $HEATMAPWIDTH; height: $HEATMAPHEIGHT\"></div>

<script src=\"scripts/HeatLayer.js\"></script>
<script src=\"scripts/leaflet-heat.js\"></script>
<script src=\"scripts/planeheatdata-\$(date -d \"$FENCEDATE\" +\"%y%m%d\").js\"></script>
<script>
    var map = L.map('map').setView([parseFloat(\"$LAT_VIS\"), parseFloat(\"$LON_VIS\")], parseInt(\"$HEATMAPZOOM\"));
    var tiles = L.tileLayer('https://{s}.tile.osm.org/{z}/{x}/{y}.png', {
        attribution: '<a href=\"https://github.com/Leaflet/Leaflet.heat\">Leaflet.heat</a> , &copy; <a href=\"http://osm.org/copyright\">OpenStreetMap</a> contributors',
    }).addTo(map);

    addressPoints = addressPoints.map(function (p) { return [p[0], p[1]]; });
    var heat = L.heatLayer(addressPoints, {
        minOpacity: 1,
        radius: 7,
        maxZoom: 14,
        blur: 11,
        attribution: \"<a href=https://github.com/sdr-enthusiasts/docker-planefence target=_blank>docker-planefence</a>\"
    }).addTo(map);
    var circle = L.circle([ parseFloat(\"$LAT_VIS\"), parseFloat(\"$LON_VIS\")], {
        color: 'blue',
        fillColor: '#f03',
        fillOpacity: 0.1,
        radius: $DISTMTS
    }).addTo(map);
"

if [[ "$OPENAIP_LAYER" == "ON" ]]
then
	cat <<EOF >>"$PLANEHEATHTML"
    var openaip_cached_basemap = new L.TileLayer("https://{s}.api.tiles.openaip.net/api/data/openaip/{z}/{x}/{y}.png?apiKey=$OPENAIPKEY", {
        attribution: "<a href=http://www.openaip.net>OpenAIP.net</a>"
    }).addTo(map);

EOF
fi
cat <<EOF >>"$PLANEHEATHTML"

</script>

EOF
