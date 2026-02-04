# The message delta object

Represents a message delta i.e. any changed fields on a message during streaming.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The identifier of the message, which can be referenced in API endpoints. |
| `object` | string | Yes |  | `thread.message.delta` | The object type, which is always `thread.message.delta`. |
| `delta` | object (2 properties) | Yes |  |  | The delta containing the fields that have changed on the Message. |

## Property Details

### `id` (required)

The identifier of the message, which can be referenced in API endpoints.

**Type**: string

### `object` (required)

The object type, which is always `thread.message.delta`.

**Type**: string

**Allowed values**: `thread.message.delta`

### `delta` (required)

The delta containing the fields that have changed on the Message.

**Type**: object (2 properties)

**Nested Properties**:

* `role`, `content`

## Example

```json
{
  "id": "msg_123",
  "object": "thread.message.delta",
  "delta": {
    "content": [
      {
        "index": 0,
        "type": "text",
        "text": { "value": "Hello", "annotations": [] }
      }
    ]
  }
}

```

