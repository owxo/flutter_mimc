# flutter_mimc example

Generic login, message, ACK, and RTS test application.

All live-test values must be supplied at runtime. The repository intentionally
contains no production endpoint, application ID, account ID, or credential.

```bash
export MIMC_APP_ID='<MIMC_APP_ID>'
export MIMC_TOKEN_ENDPOINT='https://api.example.com/api/mimc/token'
export MIMC_ACCOUNT='<TEST_ACCOUNT_A>'
export MIMC_PEER_ACCOUNT='<TEST_ACCOUNT_B>'
export MIMC_TEST_AUTH_TOKEN='<LOCAL_TEST_TOKEN>'

../tool/run_live_e2e.sh macos
```

Production clients must derive `appAccount` from the authenticated backend
user and fetch Xiaomi's complete token JSON through their own backend.
