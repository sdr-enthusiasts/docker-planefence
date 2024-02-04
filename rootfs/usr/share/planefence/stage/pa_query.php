<?php
  if(isset($_GET['hex'])) {
    $hex = "hex=" . $_GET['hex'];
  } else { $hex = ""; }

  if(isset($_GET['tail'])) {
    $tail = "tail=" . $_GET['tail'];
  } else { $tail = ""; }

  if(isset($_GET['name'])) {
    $name = "name=" . $_GET['name'];
  } else { $name = ""; }

  if(isset($_GET['equipment'])) {
    $equipment = "equipment=" . $_GET['equipment'];
  } else { $equipment = ""; }

  if(isset($_GET['timestamp'])) {
    $timestamp = "timestamp=" . $_GET['timestamp'];
  } else { $timestamp = ""; }

  if(isset($_GET['call'])) {
    $call = "call=" . $_GET['call'];
  } else { $call = ""; }

  if(isset($_GET['lat'])) {
    $lat = "lat=" . $_GET['lat'];
  } else { $lat = ""; }

  if(isset($_GET['lon'])) {
    $lon = "lon=" . $_GET['lon'];
  } else { $lon = ""; }

  if(isset($_GET['type'])) {
    $outputtype = "type=" . $_GET['type'];
  } else { $outputtype = ""; }

  if (strcmp($hex . $tail . $name . $equipment . $timestamp . $call . $lat . $lon , "") == 0) {
	   echo "<html><body><H1>PlaneFence Query Interface</H1>";
	   echo "<h3>Usage: http://" . $_SERVER['SERVER_NAME'] . $_SERVER['REQUEST_URI'] . "?hex=regex&amp;tail=regex&name=regex&amp;equipment=regex&amp;timestamp=regex&amp;call=regex&amp;lat=regex&amp;lon=regex&amp;type=csv|json</h3>";
	   echo "This will read the PlaneFence database and return matching records in JSON format.<br />";
	   echo "<br />";
	   echo "At least one argument of hex, tail, name, equipment, timestamp, call, lat, lon must be present.<br />";
	   echo "It will do a &quot;fuzzy&quot; match, or you can use a Regular Expression.<br />";
	   echo "<br />";
	   echo "The optional type argument indicates if the data returned will be json (default if omitted) or csv.<br />";
	   echo "<br />";
	   echo "For example:<br />";
	   echo "<b>http://" . $_SERVER['SERVER_NAME'] . $_SERVER['REQUEST_URI'] . "?tail=N14[1-3]NE&amp;timestamp=2021/12/2.</b><br />";
	   echo "will return records of tail N141NE, N142NE, N143NE, and that have a timestamp that contains 2021/12/20 - 2021/21/29.<br />";
	   echo "<br />";
	   echo "Note that the date range is limited to the data available to Plane-Alert.<hr />";
	   echo "(C)opyright 2021-2024 by kx1t, available under GPL3 as defined at <a href=https://github.com/sdr-enthusiasts/docker-planefence>the PlaneFence repository at GitHub</a>.<br />";
     echo "<hr>" . $hex . $tail . $name . $equipment . $timestamp . $call . $lat . $lon;
	   echo "</body></html>";
  } else {
     if (strcmp($outputtype, "csv") == 0) {
        header('Content-Type: text/csv');
     } else {
        header('Content-Type: application/json');
     }
     system("/usr/share/plane-alert/pa_query.sh " . escapeshellarg($hex) . " "  . escapeshellarg($tail) . " " . escapeshellarg($name) . " " . escapeshellarg($equipment) . " " . escapeshellarg($timestamp) . " " . escapeshellarg($call) . " " . escapeshellarg($lat) . " " . escapeshellarg($lon) . " " . escapeshellarg($outputtype), $return_value );
     ($return_value == 0) or die("#php error returned an error: $return_value");
  }
?>
