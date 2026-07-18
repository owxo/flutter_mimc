<?php

declare(strict_types=1);

namespace FlutterMimc\Backend;

use JsonException;
use RuntimeException;

final class MimcTokenService
{
    private const DEFAULT_ENDPOINT = 'https://mimc.chat.xiaomi.net/api/account/token';

    public function __construct(
        private readonly string $appId,
        private readonly string $appKey,
        private readonly string $appSecret,
        private readonly string $endpoint = self::DEFAULT_ENDPOINT,
        private readonly int $timeoutSeconds = 10,
    ) {
        if ($this->appId === '' || !ctype_digit($this->appId)) {
            throw new RuntimeException('MIMC_APP_ID must be a positive integer string');
        }
        if ($this->appKey === '') {
            throw new RuntimeException('MIMC_APP_KEY is required');
        }
        if ($this->appSecret === '') {
            throw new RuntimeException('MIMC_APP_SECRET is required');
        }
        if (!filter_var($this->endpoint, FILTER_VALIDATE_URL)) {
            throw new RuntimeException('MIMC_TOKEN_UPSTREAM must be a valid URL');
        }
        if ($this->timeoutSeconds <= 0) {
            throw new RuntimeException('MIMC_TOKEN_TIMEOUT must be greater than zero');
        }
    }

    public static function fromEnvironment(): self
    {
        return new self(
            self::requiredEnvironment('MIMC_APP_ID'),
            self::requiredEnvironment('MIMC_APP_KEY'),
            self::requiredEnvironment('MIMC_APP_SECRET'),
            self::environment('MIMC_TOKEN_UPSTREAM') ?: self::DEFAULT_ENDPOINT,
            self::positiveIntegerEnvironment('MIMC_TOKEN_TIMEOUT', 10),
        );
    }

    /**
     * Returns the unmodified JSON body required by the MIMC SDK token callback.
     */
    public function fetchForAccount(string $appAccount): string
    {
        $appAccount = trim($appAccount);
        if ($appAccount === '') {
            throw new RuntimeException('The authenticated user id is empty');
        }
        if (strlen($appAccount) > 256) {
            throw new RuntimeException('The authenticated user id exceeds 256 UTF-8 bytes');
        }

        try {
            $requestBody = json_encode(
                [
                    'appId' => $this->appId,
                    'appKey' => $this->appKey,
                    'appSecret' => $this->appSecret,
                    'appAccount' => $appAccount,
                ],
                JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR,
            );
        } catch (JsonException $error) {
            throw new RuntimeException('Unable to encode the MIMC token request', 0, $error);
        }

        [$status, $responseBody] = function_exists('curl_init')
            ? $this->postWithCurl($requestBody)
            : $this->postWithStreams($requestBody);

        if ($status < 200 || $status >= 300) {
            throw new RuntimeException("MIMC token service returned HTTP {$status}");
        }

        try {
            $response = json_decode($responseBody, true, flags: JSON_THROW_ON_ERROR);
        } catch (JsonException $error) {
            throw new RuntimeException('MIMC token service returned invalid JSON', 0, $error);
        }

        if (!is_array($response) || ($response['code'] ?? null) !== 200) {
            $message = is_array($response) && is_string($response['message'] ?? null)
                ? $response['message']
                : 'unknown error';
            throw new RuntimeException("MIMC token service rejected the request: {$message}");
        }
        if (!is_string($response['data']['token'] ?? null) || $response['data']['token'] === '') {
            throw new RuntimeException('MIMC token response does not contain data.token');
        }

        // The plugin and all native SDKs require Xiaomi's complete original JSON.
        return $responseBody;
    }

    /** @return array{int, string} */
    private function postWithCurl(string $requestBody): array
    {
        $handle = curl_init($this->endpoint);
        if ($handle === false) {
            throw new RuntimeException('Unable to initialize cURL');
        }

        curl_setopt_array($handle, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $requestBody,
            CURLOPT_HTTPHEADER => [
                'Accept: application/json',
                'Content-Type: application/json; charset=UTF-8',
            ],
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => $this->timeoutSeconds,
            CURLOPT_TIMEOUT => $this->timeoutSeconds,
        ]);

        $responseBody = curl_exec($handle);
        if (!is_string($responseBody)) {
            $message = curl_error($handle);
            curl_close($handle);
            throw new RuntimeException("MIMC token request failed: {$message}");
        }
        $status = (int) curl_getinfo($handle, CURLINFO_RESPONSE_CODE);
        curl_close($handle);
        return [$status, $responseBody];
    }

    /** @return array{int, string} */
    private function postWithStreams(string $requestBody): array
    {
        $context = stream_context_create([
            'http' => [
                'method' => 'POST',
                'header' => "Accept: application/json\r\n"
                    . "Content-Type: application/json; charset=UTF-8\r\n",
                'content' => $requestBody,
                'ignore_errors' => true,
                'timeout' => $this->timeoutSeconds,
            ],
        ]);
        $responseBody = @file_get_contents($this->endpoint, false, $context);
        if (!is_string($responseBody)) {
            throw new RuntimeException('MIMC token request failed');
        }

        $status = 0;
        foreach ($http_response_header ?? [] as $header) {
            if (preg_match('/^HTTP\/\S+\s+(\d{3})/', $header, $matches) === 1) {
                $status = (int) $matches[1];
            }
        }
        return [$status, $responseBody];
    }

    private static function requiredEnvironment(string $name): string
    {
        $value = self::environment($name);
        if ($value === '') {
            throw new RuntimeException("{$name} is required");
        }
        return $value;
    }

    private static function environment(string $name): string
    {
        $value = getenv($name);
        return is_string($value) ? trim($value) : '';
    }

    private static function positiveIntegerEnvironment(string $name, int $fallback): int
    {
        $value = self::environment($name);
        if ($value === '') {
            return $fallback;
        }
        $parsed = filter_var($value, FILTER_VALIDATE_INT, [
            'options' => ['min_range' => 1],
        ]);
        if (!is_int($parsed)) {
            throw new RuntimeException("{$name} must be a positive integer");
        }
        return $parsed;
    }
}
