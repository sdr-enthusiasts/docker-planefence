<?php
  $target = "";
  $action = "";
  $uuid = "";
  $mode = "";

  if(isset($_GET['action'])) {
    $action = $_GET['action'];
  }
  if ($action != "add" && $action != "delete") {
      die("Invalid action specified, must be either 'add' or 'delete'.");
  }

  if(isset($_GET['term'])) {
    $target = $_GET['term'];
  } else {
    die("You must specify a term parameter.");
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

  system("/scripts/manage_ignore.sh " . escapeshellarg($mode) . " " . escapeshellarg($action) . " " . escapeshellarg($target) . " " . escapeshellarg($uuid), $return_value );
  ($return_value == 0) or die("#php error returned an error: $return_value");

  if (isset($_GET['callback'])) {
    $callback_url = $_GET['callback'];
    if (strpos($callback_url, "?") === false) {
      $callback_url .= "?";
    } else {
      $callback_url .= "&";
    }
    $callback_url .= "token=" . urlencode(substr($uuid, 0, 8));
    
    header("Location:" . $callback_url);
    die;
  } else {
    echo $action . " of " . $target . " for " . $mode . " was successful, but no callback URL was provided. Press the back button in your browser to return to the previous page.";
  } 
?>
