# The model object

Describes an OpenAI model offering that can be used with the API.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The model identifier, which can be referenced in the API endpoints. |
| `created` | integer | Yes |  |  | The Unix timestamp (in seconds) when the model was created. |
| `object` | string | Yes |  | `model` | The object type, which is always "model". |
| `owned_by` | string | Yes |  |  | The organization that owns the model. |

## Property Details

### `id` (required)

The model identifier, which can be referenced in the API endpoints.

**Type**: string

### `created` (required)

The Unix timestamp (in seconds) when the model was created.

**Type**: integer

### `object` (required)

The object type, which is always "model".

**Type**: string

**Allowed values**: `model`

### `owned_by` (required)

The organization that owns the model.

**Type**: string

## Example

```json
{
  "id": "VAR_chat_model_id",
  "object": "model",
  "created": 1686935002,
  "owned_by": "openai"
}

```

