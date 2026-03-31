<?php

declare(strict_types=1);

function pf_cfg_paths(): array {
  return [
    'template' => '/usr/share/planefence/stage/persist/planefence.config.RENAME-and-EDIT-me',
    'config' => '/usr/share/planefence/persist/planefence.config',
    'uiSchemaPersist' => '/usr/share/planefence/persist/.internal/config-ui.schema.json',
    'uiSchemaStage' => '/usr/share/planefence/stage/persist/.internal/config-ui.schema.json',
    'backupDir' => '/usr/share/planefence/persist/config-backups',
    'requiredMarker' => '/run/planefence/configuration-required',
  ];
}

function pf_cfg_read_raw(string $file): array {
  if (!is_file($file)) return [];
  $lines = @file($file, FILE_IGNORE_NEW_LINES);
  return is_array($lines) ? $lines : [];
}

function pf_cfg_strip_inline_comment(string $raw): string {
  $out = '';
  $inSingle = false;
  $inDouble = false;
  $len = strlen($raw);
  for ($i = 0; $i < $len; $i++) {
    $c = $raw[$i];
    if ($inSingle) {
      if ($c === "'") $inSingle = false;
      $out .= $c;
      continue;
    }
    if ($inDouble) {
      if ($c === '"') $inDouble = false;
      $out .= $c;
      continue;
    }
    if ($c === "'") {
      $inSingle = true;
      $out .= $c;
      continue;
    }
    if ($c === '"') {
      $inDouble = true;
      $out .= $c;
      continue;
    }
    if ($c === '\\' && $i + 1 < $len && $raw[$i + 1] === '#') {
      $out .= '#';
      $i++;
      continue;
    }
    if ($c === '#') break;
    $out .= $c;
  }
  return trim($out);
}

function pf_cfg_unquote(string $v): string {
  $v = trim($v);
  if (strlen($v) >= 2) {
    $f = $v[0];
    $l = $v[strlen($v) - 1];
    if (($f === '"' || $f === "'") && $f === $l) {
      $v = substr($v, 1, -1);
      if ($f === '"') $v = stripcslashes($v);
    }
  }
  return $v;
}

function pf_cfg_parse_assignments(string $file): array {
  $out = [];
  foreach (pf_cfg_read_raw($file) as $line) {
    if (preg_match('/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/', $line, $m)) {
      $key = $m[1];
      $val = pf_cfg_unquote(pf_cfg_strip_inline_comment($m[2]));
      $out[$key] = $val;
    }
  }
  return $out;
}

function pf_cfg_fixed_options(): array {
  return [
    'GENERATE_CSV' => ['OFF', 'ON'],
    'PF_DISTUNIT' => ['kilometer', 'nauticalmile', 'mile', 'meter'],
    'PF_ALTUNIT' => ['meter', 'feet'],
    'PF_SPEEDUNIT' => ['kilometerph', 'knotph', 'mileph'],
    'PF_CHECKROUTE' => ['true', 'false'],
    'PF_OPENAIP_LAYER' => ['OFF', 'ON'],
    'PLANEFENCE' => ['enabled', 'disabled'],
    'PLANEALERT' => ['enabled', 'disabled'],
    'PF_TABLESIZE' => ['10', '25', '50', '100', 'all'],
    'PA_TABLESIZE' => ['10', '25', '50', '100', 'all'],
    'PA_COLLECT_CANDIDATES' => ['ON', 'OFF'],
    'PA_SHOW_STALE_PAGE' => ['', 'true', 'false'],
    'PF_NOTIFEVERY' => ['true', 'false'],
    'PF_NOTIF_BEHAVIOR' => ['pre', 'post'],
    'PA_DISCORD' => ['OFF', 'ON'],
    'PF_DISCORD' => ['OFF', 'ON'],
    'PF_MASTODON' => ['OFF', 'ON'],
    'PA_MASTODON' => ['OFF', 'ON'],
    'PF_MASTODON_VISIBILITY' => ['public', 'unlisted', 'private'],
    'PA_MASTODON_VISIBILITY' => ['public', 'unlisted', 'private'],
    'PF_TELEGRAM_ENABLED' => ['true', 'false'],
    'PA_TELEGRAM_ENABLED' => ['true', 'false'],
    'PF_TELEGRAM_CHAT_TYPE' => ['normal', 'dm'],
    'PA_TELEGRAM_CHAT_TYPE' => ['normal', 'dm'],
  ];
}

function pf_cfg_encode_single_quoted(string $value): string {
  $value = str_replace(["\r", "\n"], '', $value);
  $escaped = str_replace("'", "'\\''", $value);
  return "'" . $escaped . "'";
}

function pf_cfg_multi_fields(): array {
  return [
    'PF_PA_SQUAWKS' => ',',
    'PF_ALERTLIST' => ',',
    'PA_EXCLUSIONS' => ',',
    'PA_DISCORD_WEBHOOKS' => ',',
    'PF_DISCORD_WEBHOOKS' => ',',
    'PF_MQTT_FIELDS' => ',',
    'PA_MQTT_FIELDS' => ',',
  ];
}

function pf_cfg_changed_keys(array $before, array $after, array $orderedKeys): array {
  $changed = [];
  foreach ($orderedKeys as $k) {
    $old = trim((string)($before[$k] ?? ''));
    $new = trim((string)($after[$k] ?? ''));
    if ($old !== $new) $changed[] = $k;
  }
  return $changed;
}

function pf_cfg_restart_trigger_keys(array $template): array {
  $keys = [];
  foreach (($template['sections'] ?? []) as $section) {
    $title = strtolower(trim((string)($section['title'] ?? '')));
    if ($title === '') continue;
    $isRequired = str_contains($title, 'required');
    $isGeneral = str_contains($title, 'general');
    if (!$isRequired && !$isGeneral) continue;
    foreach (($section['fields'] ?? []) as $field) {
      $name = (string)($field['name'] ?? '');
      if ($name !== '') $keys[$name] = true;
    }
  }

  $keys['PF_HTTP_PORT'] = true;
  $keys['PF_CONFIG_HTTP_PORT'] = true;

  return array_keys($keys);
}

function pf_cfg_should_restart_services(array $changedKeys, array $template): bool {
  if (count($changedKeys) === 0) return false;
  $triggers = array_fill_keys(pf_cfg_restart_trigger_keys($template), true);
  foreach ($changedKeys as $k) {
    if (isset($triggers[$k])) return true;
  }
  return false;
}

function pf_cfg_restart_all_services(): array {
  $script = <<<'SH'
source /scripts/pf-common
log_print INFO "Terminating all s6 services"
kill 1
SH;

  $bg = "(\n" . rtrim($script) . "\n) &";
  $cmd = '/bin/sh -c ' . escapeshellarg($bg) . ' 2>&1';
  $output = [];
  $rc = 0;
  @exec($cmd, $output, $rc);
  return [
    'ok' => ($rc === 0),
    'exitCode' => $rc,
    'output' => trim(implode("\n", $output)),
  ];
}

function pf_cfg_log_warn(string $message): void {
  $msg = str_replace(["\r", "\n"], ' ', trim($message));
  if ($msg === '') return;
  $script = "source /scripts/pf-common\nlog_print WARN " . escapeshellarg($msg);
  $cmd = '/bin/sh -c ' . escapeshellarg($script) . ' 2>&1';
  @exec($cmd);
}

function pf_cfg_options_from_comment(string $comment): array {
  if (preg_match('/(?:Allowed|Choose)\s*:\s*([^\.\n]+)/i', $comment, $m)) {
    $raw = trim($m[1]);
    $parts = preg_split('/\s*,\s*/', $raw) ?: [];
    $parts = array_values(array_filter(array_map(static fn($x) => trim($x, " \t\n\r\0\x0B.()'\""), $parts), static fn($x) => $x !== ''));
    return array_values(array_unique($parts));
  }
  return [];
}

function pf_cfg_clean_description(string $name, string $desc): string {
  $desc = trim($desc);
  if ($desc === '' || $name === '') return $desc;
  $pattern = '/^\s*' . preg_quote($name, '/') . '\s*:\s*/i';
  $clean = preg_replace($pattern, '', $desc, 1);
  return is_string($clean) ? trim($clean) : $desc;
}

function pf_cfg_section_id(string $title): string {
  $id = strtolower($title);
  $id = preg_replace('/[^a-z0-9]+/', '-', $id ?? '') ?? 'general';
  $id = trim($id, '-');
  return $id !== '' ? $id : 'general';
}

function pf_cfg_parse_template(): array {
  $paths = pf_cfg_paths();
  $lines = pf_cfg_read_raw($paths['template']);
  $sections = [];
  $sectionOrder = [];
  $defaults = [];

  $currentTitle = 'General Parameters';
  $currentId = pf_cfg_section_id($currentTitle);
  $expectHeading = false;
  $commentBuf = [];

  $ensureSection = static function(string $sid, string $title) use (&$sections, &$sectionOrder): void {
    if (!isset($sections[$sid])) {
      $sections[$sid] = ['id' => $sid, 'title' => $title, 'fields' => []];
      $sectionOrder[] = $sid;
    }
  };
  $ensureSection($currentId, $currentTitle);

  foreach ($lines as $line) {
    if (preg_match('/^#{8,}\s*$/', trim($line))) {
      $expectHeading = true;
      continue;
    }

    if ($expectHeading && preg_match('/^#\s*([^#].*?)\s*$/', $line, $m)) {
      $candidate = trim($m[1]);
      $looksLikeSectionTitle =
        $candidate !== '' &&
        !preg_match('/^-+$/', $candidate) &&
        !str_contains($candidate, ':') &&
        !str_contains($candidate, '.') &&
        preg_match('/^[A-Za-z0-9&+\-\/ ]+$/', $candidate);
      if ($looksLikeSectionTitle) {
        $currentTitle = $candidate;
        $currentId = pf_cfg_section_id($currentTitle);
        $ensureSection($currentId, $currentTitle);
        $commentBuf = [];
        $expectHeading = false;
        continue;
      }
    }
    $expectHeading = false;

    if (preg_match('/^#\s*-{3,}\s*$/', $line)) {
      continue;
    }

    if (preg_match('/^#\s?(.*)$/', $line, $m)) {
      $txt = trim($m[1]);
      if ($txt !== '') $commentBuf[] = $txt;
      continue;
    }

    if (preg_match('/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/', $line, $m)) {
      $name = $m[1];
      $default = pf_cfg_unquote(pf_cfg_strip_inline_comment($m[2]));
      $defaults[$name] = $default;
      $desc = pf_cfg_clean_description($name, trim(implode(' ', $commentBuf)));
      $example = '';
      foreach ($commentBuf as $cLine) {
        if (stripos($cLine, 'example') !== false || stripos($cLine, 'e.g.') !== false) {
          $example = $cLine;
          break;
        }
      }
      $fixed = pf_cfg_fixed_options();
      $multi = pf_cfg_multi_fields();
      $options = $fixed[$name] ?? pf_cfg_options_from_comment($desc);
      $delimiter = $multi[$name] ?? ((stripos($desc, 'semicolon-separated') !== false) ? ';' : ',');
      $isMulti = isset($multi[$name]) || stripos($desc, 'comma-separated') !== false || stripos($desc, 'semicolon-separated') !== false;
      $fieldType = count($options) > 0 ? 'select' : ((strlen($default) > 100 || strlen($desc) > 200) ? 'textarea' : 'text');

      $sections[$currentId]['fields'][] = [
        'name' => $name,
        'label' => $name,
        'description' => $desc,
        'example' => $example,
        'defaultValue' => $default,
        'type' => $fieldType,
        'options' => $options,
        'multi' => $isMulti,
        'delimiter' => $delimiter,
      ];
      $commentBuf = [];
      continue;
    }

    if (trim($line) === '') {
      continue;
    }

    $commentBuf = [];
  }

  $orderedSections = [];
  foreach ($sectionOrder as $sid) $orderedSections[] = $sections[$sid];

  return [
    'sections' => $orderedSections,
    'defaults' => $defaults,
  ];
}

function pf_cfg_is_setup_required(array $vals, array $defaults): bool {
  $lat = trim((string)($vals['FEEDER_LAT'] ?? ''));
  $lon = trim((string)($vals['FEEDER_LONG'] ?? ''));
  if ($lat === '' || $lon === '') return true;
  $defLat = trim((string)($defaults['FEEDER_LAT'] ?? '90.12345'));
  $defLon = trim((string)($defaults['FEEDER_LONG'] ?? '-70.12345'));
  return $lat === $defLat || $lon === $defLon;
}

function pf_cfg_host_base(): string {
  $hostHeader = (string)($_SERVER['HTTP_HOST'] ?? 'localhost');
  $hostOnly = preg_replace('/:\d+$/', '', $hostHeader) ?: 'localhost';
  $https = (!empty($_SERVER['HTTPS']) && strtolower((string)$_SERVER['HTTPS']) !== 'off');
  $proto = $https ? 'https' : 'http';
  return $proto . '://' . $hostOnly;
}

function pf_cfg_status_payload(): array {
  $paths = pf_cfg_paths();
  $template = pf_cfg_parse_template();
  if (!is_file($paths['config']) && is_file($paths['template'])) {
    @copy($paths['template'], $paths['config']);
    @chmod($paths['config'], 0666);
  }
  $vals = pf_cfg_parse_assignments($paths['config']);
  $setupRequired = pf_cfg_is_setup_required($vals, $template['defaults']);
  $cfgPort = trim((string)($vals['PF_CONFIG_HTTP_PORT'] ?? '9999'));
  if (!preg_match('/^[0-9]{2,5}$/', $cfgPort)) $cfgPort = '9999';
  $url = pf_cfg_host_base() . ':' . $cfgPort . '/';

  return [
    'ok' => true,
    'setupRequired' => $setupRequired,
    'configPort' => (int)$cfgPort,
    'configUrl' => $url,
    'instanceName' => (string)($vals['PF_NAME'] ?? ($template['defaults']['PF_NAME'] ?? 'Planefence')),
  ];
}

function pf_cfg_encode_value(string $value): string {
  $value = str_replace(["\r", "\n"], '', $value);
  if ($value === '') return '""';
  if (preg_match('/^[A-Za-z0-9._:\/@,+-]+$/', $value)) {
    return $value;
  }
  $escaped = str_replace(['\\', '"'], ['\\\\', '\\"'], $value);
  return '"' . $escaped . '"';
}

function pf_cfg_notification_mechanism(string $fieldName): string {
  $n = strtoupper($fieldName);
  if (strpos($n, 'DISCORD') !== false) return 'discord';
  if (strpos($n, 'MASTODON') !== false) return 'mastodon';
  if (strpos($n, 'MQTT') !== false) return 'mqtt';
  if (strpos($n, 'RSS') !== false) return 'rss';
  if (strpos($n, 'BLUESKY') !== false) return 'bluesky';
  if (strpos($n, 'TELEGRAM') !== false) return 'telegram';
  return 'general';
}

function pf_cfg_field_map(array $sections): array {
  $map = [];
  foreach ($sections as $section) {
    foreach (($section['fields'] ?? []) as $field) {
      $name = (string)($field['name'] ?? '');
      if ($name !== '') $map[$name] = $field;
    }
  }
  return $map;
}

function pf_cfg_sections_by_title(array $sections): array {
  $out = [];
  foreach ($sections as $section) {
    $title = (string)($section['title'] ?? '');
    if ($title === '') continue;
    $out[$title] = $section;
    $norm = strtolower(trim(preg_replace('/\s+/', ' ', $title) ?? ''));
    if ($norm !== '') $out[$norm] = $section;
  }
  return $out;
}

function pf_cfg_load_ui_schema(): array {
  $paths = pf_cfg_paths();
  $candidates = [$paths['uiSchemaPersist'], $paths['uiSchemaStage']];
  foreach ($candidates as $file) {
    if (!is_file($file)) continue;
    $raw = @file_get_contents($file);
    if (!is_string($raw) || trim($raw) === '') continue;
    $decoded = json_decode($raw, true);
    if (is_array($decoded)) return $decoded;
  }
  return [];
}

function pf_cfg_apply_field_override(array $field, array $overrides): array {
  $name = (string)($field['name'] ?? '');
  if ($name === '' || !isset($overrides[$name]) || !is_array($overrides[$name])) return $field;
  $o = $overrides[$name];
  foreach (['label', 'description', 'example', 'type', 'delimiter', 'defaultValue'] as $k) {
    if (array_key_exists($k, $o)) $field[$k] = $o[$k];
  }
  if (array_key_exists('multi', $o)) $field['multi'] = (bool)$o['multi'];
  if (array_key_exists('useDefaultWhenEmpty', $o)) $field['useDefaultWhenEmpty'] = (bool)$o['useDefaultWhenEmpty'];
  if (array_key_exists('options', $o) && is_array($o['options'])) $field['options'] = array_values($o['options']);
  return $field;
}

function pf_cfg_select_fields_from_names(array $names, array $fieldMap, array $values, array $fieldOverrides): array {
  $out = [];
  foreach ($names as $name) {
    $n = (string)$name;
    if ($n === '' || !isset($fieldMap[$n])) continue;
    $field = $fieldMap[$n];
    $field = pf_cfg_apply_field_override($field, $fieldOverrides);
    $defaultValue = (string)($field['defaultValue'] ?? '');
    $hasIncoming = array_key_exists($n, $values);
    $incomingValue = (string)($values[$n] ?? '');
    $useDefaultWhenEmpty = (bool)($field['useDefaultWhenEmpty'] ?? false);
    if (!$hasIncoming) {
      $field['value'] = $defaultValue;
    } else {
      $field['value'] = ($incomingValue === '' && $useDefaultWhenEmpty) ? $defaultValue : $incomingValue;
    }
    $out[] = $field;
  }
  return $out;
}

function pf_cfg_names_for_match(string $match, array $sourceFields): array {
  $match = strtolower(trim($match));
  if ($match === '' || $match === 'all') {
    return array_map(static fn($f) => (string)($f['name'] ?? ''), $sourceFields);
  }
  return array_values(array_filter(
    array_map(static function($f) use ($match) {
      $name = (string)($f['name'] ?? '');
      if ($name === '') return '';
      return pf_cfg_notification_mechanism($name) === $match ? $name : '';
    }, $sourceFields),
    static fn($x) => $x !== ''
  ));
}

function pf_cfg_build_default_ui(array $sections, array $values, array $schema): array {
  $fieldOverrides = is_array($schema['fieldOverrides'] ?? null) ? $schema['fieldOverrides'] : [];
  $tabs = [];
  foreach ($sections as $idx => $section) {
    $title = (string)($section['title'] ?? ('Section ' . ($idx + 1)));
    $tab = [
      'id' => 'tab-' . $idx,
      'title' => $title,
      'description' => (string)($section['description'] ?? ''),
      'fields' => [],
      'subtabs' => [],
    ];
    $fields = $section['fields'] ?? [];
    if (stripos($title, 'notification') !== false) {
      $mechanisms = ['general', 'discord', 'mastodon', 'mqtt', 'rss', 'bluesky', 'telegram'];
      foreach ($mechanisms as $m) {
        $names = pf_cfg_names_for_match($m, $fields);
        if (count($names) === 0) continue;
        $subtabTitle = ucfirst($m);
        if ($m === 'bluesky') {
          $subtabTitle = 'BlueSky';
        } elseif ($m === 'mqtt' || $m === 'rss') {
          $subtabTitle = strtoupper($m);
        }
        $tab['subtabs'][] = [
          'id' => 'notif-' . $m,
          'title' => $subtabTitle,
          'description' => '',
          'fields' => pf_cfg_select_fields_from_names($names, pf_cfg_field_map($sections), $values, $fieldOverrides),
        ];
      }
    } else {
      $names = array_map(static fn($f) => (string)($f['name'] ?? ''), $fields);
      $tab['fields'] = pf_cfg_select_fields_from_names($names, pf_cfg_field_map($sections), $values, $fieldOverrides);
    }
    $tabs[] = $tab;
  }

  $intro = is_array($schema['intro'] ?? null) ? $schema['intro'] : [
    'title' => 'Welcome to the Planefence Configuration Wizard',
    'paragraphs' => [
      'Use the tabs to configure planefence.config for this instance.',
      'Save writes the config file and creates a dated backup. Cancel reloads values from disk.',
    ],
  ];

  return ['intro' => $intro, 'tabs' => $tabs];
}

function pf_cfg_build_ui_from_schema(array $sections, array $values, array $schema): array {
  $tabsSchema = is_array($schema['tabs'] ?? null) ? $schema['tabs'] : [];
  if (count($tabsSchema) === 0) {
    return pf_cfg_build_default_ui($sections, $values, $schema);
  }

  $fieldMap = pf_cfg_field_map($sections);
  $sectionsByTitle = pf_cfg_sections_by_title($sections);
  $fieldOverrides = is_array($schema['fieldOverrides'] ?? null) ? $schema['fieldOverrides'] : [];
  $tabs = [];

  foreach ($tabsSchema as $idx => $tabS) {
    if (!is_array($tabS)) continue;
    $sourceSection = (string)($tabS['sourceSection'] ?? '');
    $sourceFields = [];
    if ($sourceSection !== '') {
      $normSource = strtolower(trim(preg_replace('/\s+/', ' ', $sourceSection) ?? ''));
      if (isset($sectionsByTitle[$sourceSection])) {
        $sourceFields = $sectionsByTitle[$sourceSection]['fields'] ?? [];
      } elseif ($normSource !== '' && isset($sectionsByTitle[$normSource])) {
        $sourceFields = $sectionsByTitle[$normSource]['fields'] ?? [];
      }
    }

    $baseNames = [];
    if (is_array($tabS['fields'] ?? null)) {
      $baseNames = array_values(array_map(static fn($x) => (string)$x, $tabS['fields']));
    } elseif (count($sourceFields) > 0) {
      $baseNames = array_values(array_map(static fn($f) => (string)($f['name'] ?? ''), $sourceFields));
    }

    $tab = [
      'id' => (string)($tabS['id'] ?? ('tab-' . $idx)),
      'title' => (string)($tabS['title'] ?? ('Tab ' . ($idx + 1))),
      'description' => (string)($tabS['description'] ?? ''),
      'fields' => pf_cfg_select_fields_from_names($baseNames, $fieldMap, $values, $fieldOverrides),
      'subtabs' => [],
    ];

    if (is_array($tabS['subtabs'] ?? null)) {
      $tab['fields'] = [];
      foreach ($tabS['subtabs'] as $sidx => $subS) {
        if (!is_array($subS)) continue;
        $subNames = [];
        if (is_array($subS['fields'] ?? null)) {
          $subNames = array_values(array_map(static fn($x) => (string)$x, $subS['fields']));
        } elseif (isset($subS['match'])) {
          $subNames = pf_cfg_names_for_match((string)$subS['match'], $sourceFields);
        } else {
          $subNames = $baseNames;
        }
        $subFields = pf_cfg_select_fields_from_names($subNames, $fieldMap, $values, $fieldOverrides);
        if (count($subFields) === 0) continue;
        $tab['subtabs'][] = [
          'id' => (string)($subS['id'] ?? ($tab['id'] . '-sub-' . $sidx)),
          'title' => (string)($subS['title'] ?? ('Subtab ' . ($sidx + 1))),
          'description' => (string)($subS['description'] ?? ''),
          'fields' => $subFields,
        ];
      }
    }

    $hasFields = count($tab['fields']) > 0;
    $hasSubtabs = count($tab['subtabs']) > 0;
    if (!$hasFields && !$hasSubtabs) {
      continue;
    }

    $tabs[] = $tab;
  }

  $intro = is_array($schema['intro'] ?? null) ? $schema['intro'] : [
    'title' => 'Welcome to the Planefence Configuration Wizard',
    'paragraphs' => [
      'Use the tabs to configure planefence.config for this instance.',
      'Save writes the config file and creates a dated backup. Cancel reloads values from disk.',
    ],
  ];

  return ['intro' => $intro, 'tabs' => $tabs];
}

function pf_cfg_save(array $payload): array {
  $paths = pf_cfg_paths();
  $template = pf_cfg_parse_template();
  $defaults = $template['defaults'];
  $values = is_array($payload['values'] ?? null) ? $payload['values'] : [];
  $allowRestart = !array_key_exists('allowRestart', $payload) || (bool)$payload['allowRestart'];

  if (!is_dir($paths['backupDir'])) @mkdir($paths['backupDir'], 0777, true);
  if (!is_file($paths['config']) && is_file($paths['template'])) {
    @copy($paths['template'], $paths['config']);
  }

  if (!is_file($paths['config'])) {
    return ['ok' => false, 'error' => 'Unable to create planefence.config'];
  }

  $currentValues = pf_cfg_parse_assignments($paths['config']);

  $orderedKeys = [];
  foreach ($template['sections'] as $section) {
    foreach ($section['fields'] as $field) $orderedKeys[] = $field['name'];
  }

  $multiMap = pf_cfg_multi_fields();
  $normalized = [];
  foreach ($orderedKeys as $k) {
    $incoming = $values[$k] ?? ($defaults[$k] ?? '');
    if (is_array($incoming)) {
      $parts = array_values(array_filter(array_map(static fn($x) => trim((string)$x), $incoming), static fn($x) => $x !== ''));
      $incoming = implode($multiMap[$k] ?? ',', $parts);
    } else {
      $incoming = trim((string)$incoming);
    }
    $normalized[$k] = $incoming;
  }

  if (($normalized['FEEDER_LAT'] ?? '') === '') $normalized['FEEDER_LAT'] = (string)($defaults['FEEDER_LAT'] ?? '90.12345');
  if (($normalized['FEEDER_LONG'] ?? '') === '') $normalized['FEEDER_LONG'] = (string)($defaults['FEEDER_LONG'] ?? '-70.12345');

  $changedKeys = pf_cfg_changed_keys($currentValues, $normalized, $orderedKeys);

  $backupPath = $paths['backupDir'] . '/planefence.config.' . date('Ymd-His') . '.bak';
  @copy($paths['config'], $backupPath);

  $lines = pf_cfg_read_raw($paths['config']);
  $seen = [];
  $out = [];

  foreach ($lines as $line) {
    if (preg_match('/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=/', $line, $m)) {
      $k = $m[1];
      if (array_key_exists($k, $normalized)) {
        if ($k === 'PF_ALERTHEADER') {
          $out[] = $k . '=' . pf_cfg_encode_single_quoted((string)$normalized[$k]);
        } else {
          $out[] = $k . '=' . pf_cfg_encode_value((string)$normalized[$k]);
        }
        $seen[$k] = true;
        continue;
      }
    }
    $out[] = $line;
  }

  foreach ($orderedKeys as $k) {
    if (!isset($seen[$k])) {
      if ($k === 'PF_ALERTHEADER') {
        $out[] = $k . '=' . pf_cfg_encode_single_quoted((string)($normalized[$k] ?? ''));
      } else {
        $out[] = $k . '=' . pf_cfg_encode_value((string)($normalized[$k] ?? ''));
      }
    }
  }

  $tmp = $paths['config'] . '.tmp';
  $ok = @file_put_contents($tmp, implode("\n", $out) . "\n");
  if ($ok === false) return ['ok' => false, 'error' => 'Unable to write temporary config file'];
  if (!@rename($tmp, $paths['config'])) return ['ok' => false, 'error' => 'Unable to replace planefence.config'];
  @chmod($paths['config'], 0666);

  @unlink($paths['requiredMarker']);

  $restartRequired = pf_cfg_should_restart_services($changedKeys, $template);
  $restartWarning = '';
  $servicesRestarted = false;
  if ($restartRequired && $allowRestart) {
    $restartResult = pf_cfg_restart_all_services();
    $servicesRestarted = (bool)($restartResult['ok'] ?? false);
    if (!($restartResult['ok'] ?? false)) {
      $restartWarning = 'Configuration saved, but automatic service restart failed';
      $details = trim((string)($restartResult['output'] ?? ''));
      if ($details !== '') $restartWarning .= ': ' . $details;
    }
  } elseif ($restartRequired && !$allowRestart) {
    pf_cfg_log_warn('Configuration changes were made that require a container restart, but the user opted not to restart');
  }

  return [
    'ok' => true,
    'backupFile' => $backupPath,
    'servicesRestarted' => $servicesRestarted,
    'restartRequired' => $restartRequired,
    'restartSkipped' => ($restartRequired && !$allowRestart),
    'restartWarning' => $restartWarning,
  ];
}

function pf_cfg_load_payload(): array {
  $paths = pf_cfg_paths();
  $template = pf_cfg_parse_template();
  if (!is_file($paths['config']) && is_file($paths['template'])) {
    @copy($paths['template'], $paths['config']);
    @chmod($paths['config'], 0666);
  }

  $vals = pf_cfg_parse_assignments($paths['config']);
  foreach ($template['sections'] as &$section) {
    foreach ($section['fields'] as &$field) {
      $name = $field['name'];
      $field['value'] = (string)($vals[$name] ?? ($field['defaultValue'] ?? ''));
    }
  }

  $schema = pf_cfg_load_ui_schema();
  $ui = pf_cfg_build_ui_from_schema($template['sections'], $vals, $schema);

  $status = pf_cfg_status_payload();

  return [
    'ok' => true,
    'instanceName' => $status['instanceName'],
    'setupRequired' => $status['setupRequired'],
    'configUrl' => $status['configUrl'],
    'configPort' => $status['configPort'],
    'ui' => $ui,
    'sections' => $template['sections'],
  ];
}
