# Completions usage object

The aggregated completions usage details of the specific time bucket.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `organization.usage.completions.result` |  |
| `input_tokens` | integer | Yes |  |  | The aggregated number of text input tokens used, including cached tokens. For customers subscribe to scale tier, this includes scale tier tokens. |
| `input_cached_tokens` | integer | No |  |  | The aggregated number of text input tokens that has been cached from previous requests. For customers subscribe to scale tier, this includes scale tier tokens. |
| `output_tokens` | integer | Yes |  |  | The aggregated number of text output tokens used. For customers subscribe to scale tier, this includes scale tier tokens. |
| `input_audio_tokens` | integer | No |  |  | The aggregated number of audio input tokens used, including cached tokens. |
| `output_audio_tokens` | integer | No |  |  | The aggregated number of audio output tokens used. |
| `num_model_requests` | integer | Yes |  |  | The count of requests made to the model. |
| `project_id` | string | No |  |  | When `group_by=project_id`, this field provides the project ID of the grouped usage result. |
| `user_id` | string | No |  |  | When `group_by=user_id`, this field provides the user ID of the grouped usage result. |
| `api_key_id` | string | No |  |  | When `group_by=api_key_id`, this field provides the API key ID of the grouped usage result. |
| `model` | string | No |  |  | When `group_by=model`, this field provides the model name of the grouped usage result. |
| `batch` | boolean | No |  |  | When `group_by=batch`, this field tells whether the grouped usage result is batch or not. |

## Property Details

### `object` (required)

**Type**: string

**Allowed values**: `organization.usage.completions.result`

### `input_tokens` (required)

The aggregated number of text input tokens used, including cached tokens. For customers subscribe to scale tier, this includes scale tier tokens.

**Type**: integer

### `input_cached_tokens`

The aggregated number of text input tokens that has been cached from previous requests. For customers subscribe to scale tier, this includes scale tier tokens.

**Type**: integer

### `output_tokens` (required)

The aggregated number of text output tokens used. For customers subscribe to scale tier, this includes scale tier tokens.

**Type**: integer

### `input_audio_tokens`

The aggregated number of audio input tokens used, including cached tokens.

**Type**: integer

### `output_audio_tokens`

The aggregated number of audio output tokens used.

**Type**: integer

### `num_model_requests` (required)

The count of requests made to the model.

**Type**: integer

### `project_id`

When `group_by=project_id`, this field provides the project ID of the grouped usage result.

**Type**: string

**Nullable**: Yes

### `user_id`

When `group_by=user_id`, this field provides the user ID of the grouped usage result.

**Type**: string

**Nullable**: Yes

### `api_key_id`

When `group_by=api_key_id`, this field provides the API key ID of the grouped usage result.

**Type**: string

**Nullable**: Yes

### `model`

When `group_by=model`, this field provides the model name of the grouped usage result.

**Type**: string

**Nullable**: Yes

### `batch`

When `group_by=batch`, this field tells whether the grouped usage result is batch or not.

**Type**: boolean

**Nullable**: Yes

## Example

```json
{
    "object": "organization.usage.completions.result",
    "input_tokens": 5000,
    "output_tokens": 1000,
    "input_cached_tokens": 4000,
    "input_audio_tokens": 300,
    "output_audio_tokens": 200,
    "num_model_requests": 5,
    "project_id": "proj_abc",
    "user_id": "user-abc",
    "api_key_id": "key_abc",
    "model": "gpt-4o-mini-2024-07-18",
    "batch": false
}

```

