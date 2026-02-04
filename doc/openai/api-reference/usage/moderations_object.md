# Moderations usage object

The aggregated moderations usage details of the specific time bucket.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `organization.usage.moderations.result` |  |
| `input_tokens` | integer | Yes |  |  | The aggregated number of input tokens used. |
| `num_model_requests` | integer | Yes |  |  | The count of requests made to the model. |
| `project_id` | string | No |  |  | When `group_by=project_id`, this field provides the project ID of the grouped usage result. |
| `user_id` | string | No |  |  | When `group_by=user_id`, this field provides the user ID of the grouped usage result. |
| `api_key_id` | string | No |  |  | When `group_by=api_key_id`, this field provides the API key ID of the grouped usage result. |
| `model` | string | No |  |  | When `group_by=model`, this field provides the model name of the grouped usage result. |

## Property Details

### `object` (required)

**Type**: string

**Allowed values**: `organization.usage.moderations.result`

### `input_tokens` (required)

The aggregated number of input tokens used.

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
    "object": "organization.usage.moderations.result",
    "input_tokens": 20,
    "num_model_requests": 2,
    "project_id": "proj_abc",
    "user_id": "user-abc",
    "api_key_id": "key_abc",
    "model": "text-moderation"
}

```

