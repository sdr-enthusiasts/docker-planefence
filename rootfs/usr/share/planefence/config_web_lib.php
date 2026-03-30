<?php

declare(strict_types=1);

function pf_cfg_paths(): array {
    return [
        'template' => '/usr/share/planefence/stage/persist/planefence.config.RENAME-and-EDIT-me',
        'config' => '/usr/share/planefence/persist/planefence.config',
        'backupDir' => '/usr/share/planefence/persist/.internal/config-backups',
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
        'PF_NOTIF_BEHAVIOR' => ['', 'pre', 'post'],
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

function pf_cfg_options_from_comment(string $comment): array {
    if (preg_match('/(?:Allowed|Choose)\s*:\s*([^\.\n]+)/i', $comment, $m)) {
        $raw = trim($m[1]);
        $parts = preg_split('/\s*,\s*/', $raw) ?: [];
        $parts = array_values(array_filter(array_map(static fn($x) => trim($x, " \t\n\r\0\x0B.()'\""), $parts), static fn($x) => $x !== ''));
        return array_values(array_unique($parts));
    }
    return [];
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
            if ($candidate !== '' && !preg_match('/^-+$/', $candidate)) {
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
            $desc = trim(implode(' ', $commentBuf));
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
    $cfgPort = trim((string)($vals['PF_CONFIG_HTTP_PORT'] ?? '8081'));
    if (!preg_match('/^[0-9]{2,5}$/', $cfgPort)) $cfgPort = '8081';
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

function pf_cfg_save(array $payload): array {
    $paths = pf_cfg_paths();
    $template = pf_cfg_parse_template();
    $defaults = $template['defaults'];
    $values = is_array($payload['values'] ?? null) ? $payload['values'] : [];

    if (!is_dir($paths['backupDir'])) @mkdir($paths['backupDir'], 0777, true);
    if (!is_file($paths['config']) && is_file($paths['template'])) {
        @copy($paths['template'], $paths['config']);
    }

    if (!is_file($paths['config'])) {
        return ['ok' => false, 'error' => 'Unable to create planefence.config'];
    }

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

    $backupPath = $paths['backupDir'] . '/planefence.config.' . date('Ymd-His') . '.bak';
    @copy($paths['config'], $backupPath);

    $lines = pf_cfg_read_raw($paths['config']);
    $seen = [];
    $out = [];

    foreach ($lines as $line) {
        if (preg_match('/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=/', $line, $m)) {
            $k = $m[1];
            if (array_key_exists($k, $normalized)) {
                $out[] = $k . '=' . pf_cfg_encode_value((string)$normalized[$k]);
                $seen[$k] = true;
                continue;
            }
        }
        $out[] = $line;
    }

    foreach ($orderedKeys as $k) {
        if (!isset($seen[$k])) {
            $out[] = $k . '=' . pf_cfg_encode_value((string)($normalized[$k] ?? ''));
        }
    }

    $tmp = $paths['config'] . '.tmp';
    $ok = @file_put_contents($tmp, implode("\n", $out) . "\n");
    if ($ok === false) return ['ok' => false, 'error' => 'Unable to write temporary config file'];
    if (!@rename($tmp, $paths['config'])) return ['ok' => false, 'error' => 'Unable to replace planefence.config'];
    @chmod($paths['config'], 0666);

    @unlink($paths['requiredMarker']);

    return ['ok' => true, 'backupFile' => $backupPath];
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

    $status = pf_cfg_status_payload();

    return [
        'ok' => true,
        'instanceName' => $status['instanceName'],
        'setupRequired' => $status['setupRequired'],
        'configUrl' => $status['configUrl'],
        'configPort' => $status['configPort'],
        'sections' => $template['sections'],
    ];
}
