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

  system("/scripts/manage_ignore.sh " . escapeshellarg($mode) . " " . escapeshellarg($action) . " " . escapeshellarg($target) . " " . escapeshellarg($uuid), $return_value );
  ($return_value == 0) or die("#php error returned an error: $return_value");
  header("Location:".$_SERVER[HTTP_REFERER]);
  die;
?>
