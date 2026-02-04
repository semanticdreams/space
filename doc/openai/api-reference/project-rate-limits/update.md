# Modify project rate limit

`POST` `/organization/projects/{project_id}/rate_limits/{rate_limit_id}`

Updates a project rate limit.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `project_id` | string | Yes | The ID of the project. |
| `rate_limit_id` | string | Yes | The ID of the rate limit. |

## Request Body

The project rate limit update request payload.

### Content Type: `application/json`

**Type**: object (6 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `max_requests_per_1_minute` | integer | No |  |  | The maximum requests per minute. |
| `max_tokens_per_1_minute` | integer | No |  |  | The maximum tokens per minute. |
| `max_images_per_1_minute` | integer | No |  |  | The maximum images per minute. Only relevant for certain models. |
| `max_audio_megabytes_per_1_minute` | integer | No |  |  | The maximum audio megabytes per minute. Only relevant for certain models. |
| `max_requests_per_1_day` | integer | No |  |  | The maximum requests per day. Only relevant for certain models. |
| `batch_1_day_max_input_tokens` | integer | No |  |  | The maximum batch input tokens per day. Only relevant for certain models. |
## Responses

### 200 - Project rate limit updated successfully.

#### Content Type: `application/json`

**Type**: object (9 properties)

Represents a project rate limit config.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `project.rate_limit` | The object type, which is always `project.rate_limit` |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints. |
| `model` | string | Yes |  |  | The model this rate limit applies to. |
| `max_requests_per_1_minute` | integer | Yes |  |  | The maximum requests per minute. |
| `max_tokens_per_1_minute` | integer | Yes |  |  | The maximum tokens per minute. |
| `max_images_per_1_minute` | integer | No |  |  | The maximum images per minute. Only present for relevant models. |
| `max_audio_megabytes_per_1_minute` | integer | No |  |  | The maximum audio megabytes per minute. Only present for relevant models. |
| `max_requests_per_1_day` | integer | No |  |  | The maximum requests per day. Only present for relevant models. |
| `batch_1_day_max_input_tokens` | integer | No |  |  | The maximum batch input tokens per day. Only present for relevant models. |
**Example:**

```json
{
    "object": "project.rate_limit",
    "id": "rl_ada",
    "model": "ada",
    "max_requests_per_1_minute": 600,
    "max_tokens_per_1_minute": 150000,
    "max_images_per_1_minute": 10
}

```

### 400 - Error response for various conditions.

#### Content Type: `application/json`

**Type**: object (1 property)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `error` | object (4 properties) | Yes |  |  |  |
|   ↳ `param` | string | Yes |  |  |  |
|   ↳ `type` | string | Yes |  |  |  |
## Examples

### Request Examples

#### curl
```bash
curl -X POST https://api.openai.com/v1/organization/projects/proj_abc/rate_limits/rl_xxx \
  -H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
      "max_requests_per_1_minute": 500
  }'

```

### Response Example

```json
{
    "object": "project.rate_limit",
    "id": "rl-ada",
    "model": "ada",
    "max_requests_per_1_minute": 600,
    "max_tokens_per_1_minute": 150000,
    "max_images_per_1_minute": 10
  }

```

