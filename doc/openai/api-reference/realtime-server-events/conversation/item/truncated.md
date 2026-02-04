# conversation.item.truncated

Returned when an earlier assistant audio message item is truncated by the 
client with a `conversation.item.truncate` event. This event is used to 
synchronize the server's understanding of the audio with the client's playback.

This action will truncate the audio and remove the server-side text transcript 
to ensure there is no text in the context that hasn't been heard by the user.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `conversation.item.truncated` | The event type, must be `conversation.item.truncated`. |
| `item_id` | string | Yes |  |  | The ID of the assistant message item that was truncated. |
| `content_index` | integer | Yes |  |  | The index of the content part that was truncated. |
| `audio_end_ms` | integer | Yes |  |  | The duration up to which the audio was truncated, in milliseconds. <br>  |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be `conversation.item.truncated`.

**Type**: string

**Allowed values**: `conversation.item.truncated`

### `item_id` (required)

The ID of the assistant message item that was truncated.

**Type**: string

### `content_index` (required)

The index of the content part that was truncated.

**Type**: integer

### `audio_end_ms` (required)

The duration up to which the audio was truncated, in milliseconds.


**Type**: integer

## Example

```json
{
    "event_id": "event_2526",
    "type": "conversation.item.truncated",
    "item_id": "msg_004",
    "content_index": 0,
    "audio_end_ms": 1500
}

```

