# SDK Testing Guide for APISIX Gateway

This guide provides information on testing various AI service SDKs with the APISIX Gateway. The gateway provides a unified interface for accessing AI provider APIs with authentication.

## Gateway Overview

The APISIX Gateway acts as a proxy for various AI provider APIs, allowing authenticated access to these services using API keys. The gateway supports:

- Anthropic API endpoints
- OpenAI API endpoints

## Gateway URLs

### Development Environment
- Base URL: `https://lamassu.ita.chalmers.se`

## Authentication

The gateway supports two authentication methods:

1. **API Key Authentication**:
   - Send your API key in the `X-Gateway-Key` header

2. **Bearer Token Authentication**:
   - Send a Bearer token in the standard `Authorization` header
   - Format: `Authorization: Bearer your-api-key`

There should be a gateway key in a .env file at root.

## Provider Endpoints

### Anthropic API

The gateway provides SDK-compatible routes for the Anthropic API:

```
/v1/messages                       # Anthropic Messages API
/v1/count_tokens                   # Anthropic Token Counting API
```

### OpenAI API

The gateway provides SDK-compatible routes for the OpenAI API:

```
/v1/chat/completions               # OpenAI Chat Completions API
/v1/models                         # OpenAI Models API
```

## Using SDKs with the Gateway

You can use standard provider SDKs with the gateway by:

1. Setting the base URL to the gateway URL
2. Using your gateway API key for authentication, or setting the environment variable ANTRHOPIC_AUTH_TOKEN to the gateway key.
3. Use the SDK as normal

Make sure to test all known ways to authenticate against the SDKs. 

## Testing Scenarios

When testing SDKs with the gateway, consider the following scenarios:

1. **Authentication**:
   - Test with valid API key in `X-Gateway-Key` header
   - Test with valid API key in `Authorization: Bearer` header
   - Test with invalid or missing API key
   - Test with sourcing the key from an .env file
   - Test with setting up the key/auth token as an environment variable in the shell

2. **Request Functionality**:
   - Verify that standard SDK methods work through the gateway
   - Test all parameters supported by the underlying API
   - Ignore streaming capabilities (Currently not supported in the gateway)

3. **Response Handling**:
   - Verify that response objects match the SDK's expected format
   - Check error handling and error message propagation

4. **Performance**:
   - Measure latency overhead added by the gateway (compared to direct API calls)
   - Test with various payload sizes

## Expected Behavior

When properly configured, SDKs should work through the gateway as if they were connecting to the original provider API directly. The gateway handles:

1. Authentication translation
2. Request forwarding
3. Response passing

Any discrepancies between direct API access and gateway access should be reported.

## Limitations

Be aware of the following limitations when testing:

1. Some advanced features of provider APIs might not be fully supported
2. The gateway adds a small latency overhead
3. The gateway has rate limits that may differ from the underlying provider services