<?php
  // Collect supported query parameters and forward them to pf_query.sh
  $params = [
    'index'     => isset($_GET['index']) ? 'index=' . $_GET['index'] : '',
    'hex'       => isset($_GET['hex']) ? 'hex=' . $_GET['hex'] : '',
    'tail'      => isset($_GET['tail']) ? 'tail=' . $_GET['tail'] : '',
    'name'      => isset($_GET['name']) ? 'name=' . $_GET['name'] : '',
    'equipment' => isset($_GET['equipment']) ? 'equipment=' . $_GET['equipment'] : '',
    'timestamp' => isset($_GET['timestamp']) ? 'timestamp=' . $_GET['timestamp'] : '',
    'call'      => isset($_GET['call']) ? 'call=' . $_GET['call'] : '',
    'lat'       => isset($_GET['lat']) ? 'lat=' . $_GET['lat'] : '',
    'lon'       => isset($_GET['lon']) ? 'lon=' . $_GET['lon'] : '',
    'type'      => isset($_GET['type']) ? 'type=' . $_GET['type'] : '',
  ];

  // Determine if any filter argument is present (excluding type)
  $has_filter = false;
  foreach ($params as $key => $value) {
    if ($key === 'type') { continue; }
    if (strcmp($value, '') !== 0) { $has_filter = true; break; }
  }

  if ($has_filter === false) {
	  echo "<html><body><H1>Planefence Query Interface</H1>";
	  echo "<h3>Usage: http://" . $_SERVER['SERVER_NAME'] . $_SERVER['REQUEST_URI'] . "?hex=regex&tail=regex&name=regex&equipment=regex&timestamp=regex&call=regex&lat=regex&lon=regex&index=regex&type=csv|json</h3>";
	  echo "This will read the Planefence database and return matching records in JSON format.<br />";
	  echo "<br />";
	  echo "At least one argument of index, hex, tail, name, equipment, timestamp, call, lat, or lon must be present. The timestamp is in secs_since_epoch.<br />";
	  echo "It will do a \"fuzzy\" match, or you can use a Regular Expression.<br />";
	  echo "<br />";
	  echo "The optional type argument indicates if the data returned will be JSON (default if omitted) or CSV.<br />";
	  echo "<br />";
	  echo "For example:<br />";
	  echo "<b>http://" . $_SERVER['SERVER_NAME'] . $_SERVER['REQUEST_URI'] . "?hex=^A[DE]</b><br />";
	  echo "will return records of which the Hex ID starts with A followed by a D or E.<br />";
	  echo "<br />";
	  echo "Note that the date range is limited to the data available to Planefence. By default, this is set to the last 14 days.<hr />";
	  echo "(C)opyright 2021-2026 by kx1t, available under GPL3 as defined at <a href=https://github.com/sdr-enthusiasts/docker-planefence>the Planefence repository at GitHub</a>.<br />";
	  echo "</body></html>";
  } else {
     // Build argument list, skipping empty ones
     $args = [];
     foreach ($params as $value) {
       if (strcmp($value, '') !== 0) { $args[] = escapeshellarg($value); }
     }

     // Content type depends on requested output
     $outputtype = $params['type'];
     if (strcmp($outputtype, 'type=csv') === 0) {
        header('Content-Type: text/csv');
     } else {
        header('Content-Type: application/json');
     }

     $command = "/usr/share/planefence/pf_query.sh " . implode(' ', $args);
     date_default_timezone_set(date_default_timezone_get());
     $output = shell_exec($command);
     if ($output === null) {
       http_response_code(500);
       die("#php error: command failed to run");
     }
     echo $output;
     exit;
  }
?>
