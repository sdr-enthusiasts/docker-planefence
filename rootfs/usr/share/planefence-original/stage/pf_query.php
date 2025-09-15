<?php
  if(isset($_GET['hex'])) {
    $hex = "hex=" . $_GET['hex'];
  } else { $hex = ""; }

  if(isset($_GET['call'])) {
    $call = "call=" . $_GET['call'];
  } else { $call = ""; }

  if(isset($_GET['start'])) {
    $start = "start=" . $_GET['start'];
  } else { $start = ""; }

  if(isset($_GET['end'])) {
    $end = "end=" . $_GET['end'];
  } else { $end = ""; }

  if(isset($_GET['type'])) {
    $outputtype = "type=" . $_GET['type'];
  } else { $outputtype = ""; }

  if (strcmp($hex . $call . $start . $end , "") == 0) {
	   echo "<html><body><H1>Planefence Query Interface</H1>";
	   echo "<h3>Usage: http://" . $_SERVER['SERVER_NAME'] . $_SERVER['REQUEST_URI'] . "?hex=regex&call=regex&start=regex&end=regex&type=csv|json</h3>";
	   echo "This will read the Planefence database and return matching records in JSON format.<br />";
	   echo "<br />";
	   echo "At least one argument of hex, call, start, end must be present.<br />";
	   echo "It will do a &quot;fuzzy&quot; match, or you can use a Regular Expression.<br />";
	   echo "<br />";
	   echo "The optional type argument indicates if the data returned will be JSON (default if omitted) or CSV.<br />";
	   echo "<br />";
	   echo "For example:<br />";
	   echo "<b>http://" . $_SERVER['SERVER_NAME'] . $_SERVER['REQUEST_URI'] . "?hex=^A[DE]&start=2021/12/1[345]</b><br />";
	   echo "will return records of which the Hex ID starts with A followed by a D or E, and that have a start date/time that contains 2021/12/13, 2021/12/14, or 2021/12/15.<br />";
	   echo "<br />";
	   echo "Note that the date range is limited to the data available to Planefence. By default, this is set to the last 14 days.<hr />";
	   echo "(C)opyright 2021-2025 by kx1t, available under GPL3 as defined at <a href=https://github.com/sdr-enthusiasts/docker-planefence>the Planefence repository at GitHub</a>.<br />";
	   echo "</body></html>";
  } else {
     if (strcmp($outputtype, "csv") == 0) {
        header('Content-Type: text/csv');
     } else {
        header('Content-Type: application/json');
     }
     system("/usr/share/planefence/pf_query.sh " . escapeshellarg($hex) . " " . escapeshellarg($call) . " " . escapeshellarg($start) . " " . escapeshellarg($end) . " " . escapeshellarg($outputtype) . " file=/usr/share/planefence/html/*.csv", $return_value );
     ($return_value == 0) or die("#php error returned an error: $return_value");
  }
?>
