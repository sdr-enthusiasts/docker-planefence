<?php

declare(strict_types=1);
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

require_once '/usr/share/planefence/config_web_lib.php';

$action = strtolower((string)($_GET['action'] ?? 'load'));

try {
    if ($action === 'status') {
        echo json_encode(pf_cfg_status_payload(), JSON_UNESCAPED_SLASHES);
        exit;
    }

    if ($action === 'backups') {
        echo json_encode(pf_cfg_list_backups(), JSON_UNESCAPED_SLASHES);
        exit;
    }

    if ($action === 'preview_backup') {
        $name = trim((string)($_GET['name'] ?? ''));
        if ($name === '') {
            http_response_code(400);
            echo json_encode(['ok' => false, 'error' => 'Missing backup name']);
            exit;
        }
        $result = pf_cfg_backup_preview($name);
        if (!($result['ok'] ?? false)) http_response_code(400);
        echo json_encode($result, JSON_UNESCAPED_SLASHES);
        exit;
    }

    if ($action === 'save') {
        $body = file_get_contents('php://input');
        $payload = json_decode($body ?: '{}', true);
        if (!is_array($payload)) {
            http_response_code(400);
            echo json_encode(['ok' => false, 'error' => 'Invalid JSON payload']);
            exit;
        }
        $result = pf_cfg_save($payload);
        if (!($result['ok'] ?? false)) http_response_code(400);
        echo json_encode($result, JSON_UNESCAPED_SLASHES);
        exit;
    }

    if ($action === 'restore_backup') {
        $body = file_get_contents('php://input');
        $payload = json_decode($body ?: '{}', true);
        if (!is_array($payload)) {
            http_response_code(400);
            echo json_encode(['ok' => false, 'error' => 'Invalid JSON payload']);
            exit;
        }
        $name = trim((string)($payload['name'] ?? ''));
        if ($name === '') {
            http_response_code(400);
            echo json_encode(['ok' => false, 'error' => 'Missing backup name']);
            exit;
        }
        $result = pf_cfg_restore_backup($name);
        if (!($result['ok'] ?? false)) http_response_code(400);
        echo json_encode($result, JSON_UNESCAPED_SLASHES);
        exit;
    }

    echo json_encode(pf_cfg_load_payload(), JSON_UNESCAPED_SLASHES);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => $e->getMessage()]);
}
