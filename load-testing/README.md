# SokoVibe Load Testing

Uses Grafana k6 against the existing backend. Do not run against production without approval.

## Run smoke test

```bash
k6 run -e BASE_URL=http://localhost:5000 load-testing/smoke.js
```

## Run search test

```bash
k6 run -e BASE_URL=http://localhost:5000 load-testing/search.js
```

## Safety
- Use staging accounts only.
- No real payments, withdrawals, SMS, or email campaigns.
- Keep write tests disabled by default.
