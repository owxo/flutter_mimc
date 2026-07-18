<?php

namespace addons\mimcbridge\controller\api;

use addons\mimcbridge\library\MimcTokenService;
use app\common\controller\Api;
use RuntimeException;
use think\Response;

/**
 * MIMC token endpoint.
 *
 * @ApiSector (MIMC)
 */
class Mimc extends Api
{
    // Every action requires a valid FastAdmin member token.
    protected $noNeedLogin = [];

    // A logged-in member may fetch only their own MIMC token. No additional
    // FastAdmin rule is necessary because appAccount comes from $this->auth.
    protected $noNeedRight = ['token'];

    /**
     * @ApiTitle (获取 MIMC Token)
     * @ApiSummary (使用当前 FastAdmin 用户 ID 作为 MIMC appAccount)
     * @ApiMethod (POST)
     * @ApiHeaders (name=token, type=string, required=true, description="FastAdmin 用户 Token")
     */
    public function token()
    {
        if (!$this->request->isPost()) {
            $this->error('Method not allowed', null, 405);
        }

        $userId = (int) $this->auth->id;
        if ($userId < 1) {
            $this->error('Please login first', null, 401);
        }

        try {
            $body = MimcTokenService::fromEnvironment()->fetchForUserId($userId);
        } catch (RuntimeException $error) {
            // Log detailed upstream diagnostics only on the server. Never put
            // AppKey/AppSecret or upstream response data in the API response.
            trace('MIMC token failure for user ' . $userId . ': ' . $error->getMessage(), 'error');
            $this->error('MIMC token service unavailable', null, 502);
        }

        return Response::create($body, 'html', 200, [
            'Content-Type' => 'application/json; charset=UTF-8',
            'Cache-Control' => 'no-store',
        ]);
    }
}
