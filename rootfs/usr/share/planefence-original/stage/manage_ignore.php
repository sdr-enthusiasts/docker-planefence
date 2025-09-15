<?php
  // At the top of manage_ignore.php
  error_reporting(E_ALL);
  ini_set('display_errors', 1);

  // Detailed logging
  file_put_contents('/tmp/form_debug.log', 
      date('Y-m-d H:i:s') . "\n" . 
      'GET: ' . print_r($_GET, true) . "\n" . 
      'SERVER: ' . print_r($_SERVER, true) . "\n\n", 
      FILE_APPEND
  );

  // Print all received parameters
  // print_r($_GET);


    $target = "";
    $action = "";
    $uuid = "";
    $mode = "";

    if(isset($_GET['action'])) {
      $action = $_GET['action'];
    }
    if ($action != "add" && $action != "delete") {
      print_r($_GET);
      die("<br>Invalid action specified, must be either 'add' or 'delete'.");
    }

    if(isset($_GET['term'])) {
      $target = $_GET['term'];
    } else {
      print_r($_GET);
      die("<br>You must specify a term parameter.");
    }

    if(isset($_GET['uuid'])) {
      $uuid = $_GET['uuid'];
    } else {
      print_r($_GET);
      die("<br>You must specify a uuid parameter.");
    }

    if(isset($_GET['mode'])) {
      $mode = $_GET['mode'];
      if ($mode != "pf" && $mode != "pa") {
        print_r($_GET);
        die("<br>Invalid mode specified, must be either 'pf' or 'pa'.");
      }
    } else { 
      print_r($_GET);
      die("<br>You must specific a mode parameter, and it must be either 'pf' or 'pa'.");
    }

    system("/scripts/manage_ignore.sh " . escapeshellarg($mode) . " " . escapeshellarg($action) . " " . escapeshellarg($target) . " " . escapeshellarg($uuid), $return_value );
    ($return_value == 0) or { print_r($_GET); die("<br>#php error returned an error: $return_value"); }

    if (isset($_GET['callback'])) {
      $callback_url = $_GET['callback'];
      $callback_url = preg_replace('/(&?])token=[a-zA-Z0-9]+[?]?/i', '$1', $callback_url); // remove any existing token parameter
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
