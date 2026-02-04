# Images usage object

The aggregated images usage details of the specific time bucket.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `organization.usage.images.result` |  |
| `images` | integer | Yes |  |  | The number of images processed. |
| `num_model_requests` | integer | Yes |  |  | The count of requests made to the model. |
| `source` | string | No |  |  | When `group_by=source`, this field provides the source of the grouped usage result, possible values are `image.generation`, `image.edit`, `image.variation`. |
| `size` | string | No |  |  | When `group_by=size`, this field provides the image size of the grouped usage result. |
| `project_id` | string | No |  |  | When `group_by=project_id`, this field provides the project ID of the grouped usage result. |
| `user_id` | string | No |  |  | When `group_by=user_id`, this field provides the user ID of the grouped usage result. |
| `api_key_id` | string | No |  |  | When `group_by=api_key_id`, this field provides the API key ID of the grouped usage result. |
| `model` | string | No |  |  | When `group_by=model`, this field provides the model name of the grouped usage result. |

## Property Details

### `object` (required)

**Type**: string

**Allowed values**: `organization.usage.images.result`

### `images` (required)

The number of images processed.

**Type**: integer

### `num_model_requests` (required)

The count of requests made to the model.

**Type**: integer

### `source`

When `group_by=source`, this field provides the source of the grouped usage result, possible values are `image.generation`, `image.edit`, `image.variation`.

**Type**: string

**Nullable**: Yes

### `size`

When `group_by=size`, this field provides the image size of the grouped usage result.

**Type**: string

**Nullable**: Yes

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
    "object": "organization.usage.images.result",
    "images": 2,
    "num_model_requests": 2,
    "size": "1024x1024",
    "source": "image.generation",
    "project_id": "proj_abc",
    "user_id": "user-abc",
    "api_key_id": "key_abc",
    "model": "dall-e-3"
}

```

