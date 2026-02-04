# response.text.done

Returned when the text value of a "text" content part is done streaming. Also
emitted when a Response is interrupted, incomplete, or cancelled.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `response.text.done` | The event type, must be `response.text.done`. |
| `response_id` | string | Yes |  |  | The ID of the response. |
| `item_id` | string | Yes |  |  | The ID of the item. |
| `output_index` | integer | Yes |  |  | The index of the output item in the response. |
| `content_index` | integer | Yes |  |  | The index of the content part in the item's content array. |
| `text` | string | Yes |  |  | The final text content. |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be `response.text.done`.

**Type**: string

**Allowed values**: `response.text.done`

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

### `text` (required)

The final text content.

**Type**: string

## Example

```json
{
    "event_id": "event_4344",
    "type": "response.text.done",
    "response_id": "resp_001",
    "item_id": "msg_007",
    "output_index": 0,
    "content_index": 0,
    "text": "Sure, I can help with that."
}

```

