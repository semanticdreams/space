# input_audio_buffer.committed

Returned when an input audio buffer is committed, either by the client or 
automatically in server VAD mode. The `item_id` property is the ID of the user
message item that will be created, thus a `conversation.item.created` event 
will also be sent to the client.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `input_audio_buffer.committed` | The event type, must be `input_audio_buffer.committed`. |
| `previous_item_id` | string | Yes |  |  | The ID of the preceding item after which the new item will be inserted. <br>  |
| `item_id` | string | Yes |  |  | The ID of the user message item that will be created. |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be `input_audio_buffer.committed`.

**Type**: string

**Allowed values**: `input_audio_buffer.committed`

### `previous_item_id` (required)

The ID of the preceding item after which the new item will be inserted.


**Type**: string

### `item_id` (required)

The ID of the user message item that will be created.

**Type**: string

## Example

```json
{
    "event_id": "event_1121",
    "type": "input_audio_buffer.committed",
    "previous_item_id": "msg_001",
    "item_id": "msg_002"
}

```

