# conversation.created

Returned when a conversation is created. Emitted right after session creation.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `conversation.created` | The event type, must be `conversation.created`. |
| `conversation` | object (2 properties) | Yes |  |  | The conversation resource. |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be `conversation.created`.

**Type**: string

**Allowed values**: `conversation.created`

### `conversation` (required)

The conversation resource.

**Type**: object (2 properties)

**Nested Properties**:

* `id`, `object`

## Example

```json
{
    "event_id": "event_9101",
    "type": "conversation.created",
    "conversation": {
        "id": "conv_001",
        "object": "realtime.conversation"
    }
}

```

