<?php

namespace addons\mimcbridge\library;

use RuntimeException;

/**
 * FastAdmin-compatible (PHP 7.4+) proxy for Xiaomi's MIMC token service.
 */
class MimcTokenService
{
    const DEFAULT_ENDPOINT = 'https://mimc.chat.xiaomi.net/api/account/token';

    /** @var string */
    private $appId;
    /** @var string */
    private $appKey;
    /** @var string */
    private $appSecret;
    /** @var string */
    private $endpoint;
    /** @var int */
    private $timeout;

    public function __construct($appId, $appKey, $appSecret, $endpoint = self::DEFAULT_ENDPOINT, $timeout = 10)
    {
        $this->appId = trim((string) $appId);
        $this->appKey = trim((string) $appKey);
        $this->appSecret = trim((string) $appSecret);
        $this->endpoint = trim((string) $endpoint);
        $this->timeout = (int) $timeout;

        if ($this->appId === '' || !ctype_digit($this->appId)) {
            throw new RuntimeException('MIMC_APP_ID must be a positive integer string');
        }
        if ($this->appKey === '' || $this->appSecret === '') {
            throw new RuntimeException('MIMC server credentials are missing');
        }
        if (!filter_var($this->endpoint, FILTER_VALIDATE_URL)) {
            throw new RuntimeException('MIMC_TOKEN_UPSTREAM is invalid');
        }
        if ($this->timeout < 1) {
            throw new RuntimeException('MIMC_TOKEN_TIMEOUT must be positive');
        }
    }

    public static function fromEnvironment()
    {
        return new self(
            self::requiredEnvironment('MIMC_APP_ID'),
            self::requiredEnvironment('MIMC_APP_KEY'),
            self::requiredEnvironment('MIMC_APP_SECRET'),
            self::environment('MIMC_TOKEN_UPSTREAM') ?: self::DEFAULT_ENDPOINT,
            self::environment('MIMC_TOKEN_TIMEOUT') ?: 10
        );
    }

    /**
     * Returns Xiaomi's complete JSON response without a FastAdmin envelope.
     */
    public function fetchForUserId($userId)
    {
        $appAccount = trim((string) $userId);
        if ($appAccount === '' || strlen($appAccount) > 256) {
            throw new RuntimeException('Authenticated FastAdmin user id is invalid');
        }

        $request = json_encode([
            'appId' => $this->appId,
            'appKey' => $this->appKey,
            'appSecret' => $this->appSecret,
            'appAccount' => $appAccount,
            'regionKey' => self::environment('MIMC_REGION_KEY') ?: 'REGION_CN',
        ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        if (!is_string($request)) {
            throw new RuntimeException('Unable to encode MIMC token request');
        }

        $curl = curl_init($this->endpoint);
        if ($curl === false) {
            throw new RuntimeException('Unable to initialize MIMC token request');
        }
        curl_setopt_array($curl, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $request,
            CURLOPT_HTTPHEADER => [
                'Accept: application/json',
                'Content-Type: application/json; charset=UTF-8',
            ],
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => $this->timeout,
            CURLOPT_TIMEOUT => $this->timeout,
        ]);

        $body = curl_exec($curl);
        $error = curl_error($curl);
        $status = (int) curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
        curl_close($curl);

        if (!is_string($body)) {
            throw new RuntimeException('MIMC token request failed: ' . $error);
        }
        if ($status < 200 || $status >= 300) {
            throw new RuntimeException('MIMC token service returned HTTP ' . $status);
        }

        $decoded = json_decode($body, true);
        if (!is_array($decoded) || (int) ($decoded['code'] ?? 0) !== 200) {
            throw new RuntimeException('MIMC token service rejected the request');
        }
        if (!isset($decoded['data']['token']) || !is_string($decoded['data']['token'])) {
            throw new RuntimeException('MIMC token response is incomplete');
        }
        if ((string) ($decoded['data']['appAccount'] ?? '') !== $appAccount) {
            throw new RuntimeException('MIMC token response account mismatch');
        }

        return $body;
    }

    private static function requiredEnvironment($name)
    {
        $value = self::environment($name);
        if ($value === '') {
            throw new RuntimeException($name . ' is required');
        }
        return $value;
    }

    private static function environment($name)
    {
        $value = getenv($name);
        return is_string($value) ? trim($value) : '';
    }
}
