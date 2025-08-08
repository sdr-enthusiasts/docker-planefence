<?php
  $action = "";
  if(isset($_GET['add']) && ! isset($_GET['delete'])) {
    $target = $_GET['add'];
    $action = "add";
  }

  if(isset($_GET['delete']) && ! isset($_GET['add'])) {
    $target = $_GET['delete'];
    $action = "delete";
  }

  if ($action = "") {
    die("You must specify either an add or delete parameter, but not both.");
  }

  if(isset($_GET['uuid'])) {
    $uuid = $_GET['uuid'];
  } else {
    die("You must specify a uuid parameter.");
  }

  if(isset($_GET['mode'])) {
    $mode = $_GET['mode'];
    if ($mode != "pf" && $mode != "pa") {
      die("Invalid mode specified, must be either 'pf' or 'pa'.");
    }
  } else { 
    die("You must specific a mode parameter, and it must be either 'pf' or 'pa'.");
  }

  if ( $action == "" || $uuid == "") {
	   echo "<html><body><H1>Planefence manage_ignore Interface</H1>";
	   echo "<h3>Usage: http://" . $_SERVER['SERVER_NAME'] . $_SERVER['REQUEST_URI'] . "?add=term&uuid=UUID&mode=pf|pa</h3>";
	   echo "This will add the specified term to the ignore list.<br />";
	   echo "<br />";
	   echo "<h3>Usage: http://" . $_SERVER['SERVER_NAME'] . $_SERVER['REQUEST_URI'] . "?delete=term&uuid=UUID</h3>";
	   echo "This will delete the specified term from the ignore list.<br />";
	   echo "<br />";
     echo "At least one argument of add or delete must be present, along with the uuid of the feeder. The uuid can be found inside the container in /tmp/add_delete.uuid<br />";
     echo "<br />";
	   echo "(C)opyright 2021-2025 by kx1t, available under GPL3 as defined at <a href=https://github.com/sdr-enthusiasts/docker-planefence>the Planefence repository at GitHub</a>.<br />";
	   echo "</body></html>";
  } else {
     system("/scripts/manage_ignore.sh " . escapeshellarg($mode) . " " . escapeshellarg($action) . " " . escapeshellarg($target) . " " . escapeshellarg($uuid), $return_value );
     ($return_value == 0) or die("#php error returned an error: $return_value");
     header("Location:".$_SERVER[HTTP_REFERER]);
     
  }
  die;
?>
