# response.content_part.done

Returned when a content part is done streaming in an assistant message item.
Also emitted when a Response is interrupted, incomplete, or cancelled.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `response.content_part.done` | The event type, must be `response.content_part.done`. |
| `response_id` | string | Yes |  |  | The ID of the response. |
| `item_id` | string | Yes |  |  | The ID of the item. |
| `output_index` | integer | Yes |  |  | The index of the output item in the response. |
| `content_index` | integer | Yes |  |  | The index of the content part in the item's content array. |
| `part` | object (4 properties) | Yes |  |  | The content part that is done. |
|   ↳ `audio` | string | No |  |  | Base64-encoded audio data (if type is "audio"). |
|   ↳ `transcript` | string | No |  |  | The transcript of the audio (if type is "audio"). |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be `response.content_part.done`.

**Type**: string

**Allowed values**: `response.content_part.done`

### `response_id` (required)

The ID of the response.

**Type**: string

### `item_id` (required)

The ID of the item.

**Type**: string

### `output_index` (required)

The index of the output item in the response.

**Type**: integer

### `content_index` (required)

The index of the content part in the item's content array.

**Type**: integer

### `part` (required)

The content part that is done.

**Type**: object (4 properties)

**Nested Properties**:

* `type`, `text`, `audio`, `transcript`

## Example

```json
{
    "event_id": "event_3940",
    "type": "response.content_part.done",
    "response_id": "resp_001",
    "item_id": "msg_007",
    "output_index": 0,
    "content_index": 0,
    "part": {
        "type": "text",
        "text": "Sure, I can help with that."
    }
}

```

