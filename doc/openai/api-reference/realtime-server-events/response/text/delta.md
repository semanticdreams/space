# response.text.delta

Returned when the text value of a "text" content part is updated.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `response.text.delta` | The event type, must be `response.text.delta`. |
| `response_id` | string | Yes |  |  | The ID of the response. |
| `item_id` | string | Yes |  |  | The ID of the item. |
| `output_index` | integer | Yes |  |  | The index of the output item in the response. |
| `content_index` | integer | Yes |  |  | The index of the content part in the item's content array. |
| `delta` | string | Yes |  |  | The text delta. |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be `response.text.delta`.

**Type**: string

**Allowed values**: `response.text.delta`

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

### `delta` (required)

The text delta.

**Type**: string

## Example

```json
{
    "event_id": "event_4142",
    "type": "response.text.delta",
    "response_id": "resp_001",
    "item_id": "msg_007",
    "output_index": 0,
    "content_index": 0,
    "delta": "Sure, I can h"
}

```

