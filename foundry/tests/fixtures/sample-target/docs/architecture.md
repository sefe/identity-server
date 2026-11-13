# Architecture

The sample has one Node.js service with two externally visible surfaces:

1. an HTTP API described by `openapi.yaml`;
2. a server-rendered browser storefront.

The service owns order persistence. Automation uses environment-based base URLs
and never depends on production credentials or production data.

