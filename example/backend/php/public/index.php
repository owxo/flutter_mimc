<?php

declare(strict_types=1);

use FlutterMimc\Backend\MimcTokenService;
use RuntimeException;
use Throwable;

require dirname(__DIR__) . '/src/MimcTokenService.php';

header('Content-Type: application/json; charset=UTF-8');
header('Cache-Control: no-store');

$allowedOrigin = trim((string) getenv('MIMC_CORS_ORIGIN'));
$requestOrigin = $_SERVER['HTTP_ORIGIN'] ?? '';
if ($allowedOrigin !== '' && hash_equals($allowedOrigin, $requestOrigin)) {
    header("Access-Control-Allow-Origin: {$allowedOrigin}");
    header('Access-Control-Allow-Headers: Authorization, Content-Type');
    header('Access-Control-Allow-Methods: POST, OPTIONS');
    header('Vary: Origin');
}

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    respondWithError(405, 'method_not_allowed', 'Use POST for this endpoint');
}

try {
    $appAccount = resolveAuthenticatedUserId();
    $tokenResponse = MimcTokenService::fromEnvironment()->fetchForAccount($appAccount);
    echo $tokenResponse;
} catch (RuntimeException $error) {
    respondWithError(502, 'token_service_error', $error->getMessage());
} catch (Throwable $error) {
    respondWithError(500, 'internal_error', 'Unable to issue a MIMC token');
}

/**
 * Production: the existing PHP login middleware must set $_SESSION['user_id']
 * (or the key selected by MIMC_SESSION_USER_KEY) to the backend's unique user id.
 *
 * Local E2E: an account supplied in JSON is accepted only when test mode is
 * explicitly enabled and the request carries the configured bearer secret.
 */
function resolveAuthenticatedUserId(): string
{
    if (session_status() !== PHP_SESSION_ACTIVE) {
        session_start();
    }

    $sessionKey = trim((string) getenv('MIMC_SESSION_USER_KEY')) ?: 'user_id';
    $sessionUserId = $_SESSION[$sessionKey] ?? null;
    if (is_int($sessionUserId) || is_string($sessionUserId)) {
        $value = trim((string) $sessionUserId);
        if ($value !== '') {
            return $value;
        }
    }

    if (!environmentFlag('MIMC_TEST_MODE')) {
        respondWithError(401, 'unauthenticated', 'No authenticated backend user');
    }

    $expectedSecret = (string) getenv('MIMC_TEST_AUTH_TOKEN');
    $authorization = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if ($expectedSecret === '' || !hash_equals("Bearer {$expectedSecret}", $authorization)) {
        respondWithError(401, 'unauthenticated', 'Invalid E2E bearer token');
    }

    $body = file_get_contents('php://input');
    $decoded = is_string($body) ? json_decode($body, true) : null;
    $appAccount = is_array($decoded) ? ($decoded['appAccount'] ?? null) : null;
    if (!is_int($appAccount) && !is_string($appAccount)) {
        respondWithError(400, 'invalid_account', 'appAccount is required in E2E mode');
    }
    $value = trim((string) $appAccount);
    if ($value === '') {
        respondWithError(400, 'invalid_account', 'appAccount cannot be empty');
    }
    return $value;
}

function environmentFlag(string $name): bool
{
    $value = strtolower(trim((string) getenv($name)));
    return in_array($value, ['1', 'true', 'yes', 'on'], true);
}

function respondWithError(int $status, string $code, string $message): never
{
    http_response_code($status);
    echo json_encode(
        ['code' => $code, 'message' => $message],
        JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE,
    );
    exit;
}
