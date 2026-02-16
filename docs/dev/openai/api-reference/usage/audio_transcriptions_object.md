# Audio transcriptions usage object

The aggregated audio transcriptions usage details of the specific time bucket.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `organization.usage.audio_transcriptions.result` |  |
| `seconds` | integer | Yes |  |  | The number of seconds processed. |
| `num_model_requests` | integer | Yes |  |  | The count of requests made to the model. |
| `project_id` | string | No |  |  | When `group_by=project_id`, this field provides the project ID of the grouped usage result. |
| `user_id` | string | No |  |  | When `group_by=user_id`, this field provides the user ID of the grouped usage result. |
| `api_key_id` | string | No |  |  | When `group_by=api_key_id`, this field provides the API key ID of the grouped usage result. |
| `model` | string | No |  |  | When `group_by=model`, this field provides the model name of the grouped usage result. |

## Property Details

### `object` (required)

**Type**: string

**Allowed values**: `organization.usage.audio_transcriptions.result`

### `seconds` (required)

The number of seconds processed.

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

## Example

```json
{
    "object": "organization.usage.audio_transcriptions.result",
    "seconds": 10,
    "num_model_requests": 1,
    "project_id": "proj_abc",
    "user_id": "user-abc",
    "api_key_id": "key_abc",
    "model": "tts-1"
}

```

