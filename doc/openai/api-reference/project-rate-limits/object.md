# The project rate limit object

Represents a project rate limit config.

## Properties

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

## Property Details

### `object` (required)

The object type, which is always `project.rate_limit`

**Type**: string

**Allowed values**: `project.rate_limit`

### `id` (required)

The identifier, which can be referenced in API endpoints.

**Type**: string

### `model` (required)

The model this rate limit applies to.

**Type**: string

### `max_requests_per_1_minute` (required)

The maximum requests per minute.

**Type**: integer

### `max_tokens_per_1_minute` (required)

The maximum tokens per minute.

**Type**: integer

### `max_images_per_1_minute`

The maximum images per minute. Only present for relevant models.

**Type**: integer

### `max_audio_megabytes_per_1_minute`

The maximum audio megabytes per minute. Only present for relevant models.

**Type**: integer

### `max_requests_per_1_day`

The maximum requests per day. Only present for relevant models.

**Type**: integer

### `batch_1_day_max_input_tokens`

The maximum batch input tokens per day. Only present for relevant models.

**Type**: integer

## Example

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

