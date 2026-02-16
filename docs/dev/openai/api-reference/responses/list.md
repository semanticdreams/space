# The input item list

A list of Response items.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `list` | The type of object returned, must be `list`. |
| `data` | array of oneOf: object (5 properties) | object (5 properties) | object (5 properties) | object (6 properties) | object (6 properties) | object (3 properties) | object (6 properties) | object (5 properties) | Yes |  |  | A list of items used to generate this response. |
| `has_more` | boolean | Yes |  |  | Whether there are more items available. |
| `first_id` | string | Yes |  |  | The ID of the first item in the list. |
| `last_id` | string | Yes |  |  | The ID of the last item in the list. |

## Property Details

### `object` (required)

The type of object returned, must be `list`.

**Type**: string

**Allowed values**: `list`

### `data` (required)

A list of items used to generate this response.

**Type**: array of oneOf: object (5 properties) | object (5 properties) | object (5 properties) | object (6 properties) | object (6 properties) | object (3 properties) | object (6 properties) | object (5 properties)

### `has_more` (required)

Whether there are more items available.

**Type**: boolean

### `first_id` (required)

The ID of the first item in the list.

**Type**: string

### `last_id` (required)

The ID of the last item in the list.

**Type**: string

## Example

```json
{
  "object": "list",
  "data": [
    {
      "id": "msg_abc123",
      "type": "message",
      "role": "user",
      "content": [
        {
          "type": "input_text",
          "text": "Tell me a three sentence bedtime story about a unicorn."
        }
      ]
    }
  ],
  "first_id": "msg_abc123",
  "last_id": "msg_abc123",
  "has_more": false
}

```

