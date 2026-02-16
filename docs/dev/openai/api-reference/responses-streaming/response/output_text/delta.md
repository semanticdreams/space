# response.output_text.delta

Emitted when there is an additional text delta.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.output_text.delta` | The type of the event. Always `response.output_text.delta`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the output item that the text delta was added to. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the text delta was added to. <br>  |
| `content_index` | integer | Yes |  |  | The index of the content part that the text delta was added to. <br>  |
| `delta` | string | Yes |  |  | The text delta that was added. <br>  |

## Property Details

### `type` (required)

The type of the event. Always `response.output_text.delta`.


**Type**: string

**Allowed values**: `response.output_text.delta`

### `item_id` (required)

The ID of the output item that the text delta was added to.


**Type**: string

### `output_index` (required)

The index of the output item that the text delta was added to.


**Type**: integer

### `content_index` (required)

The index of the content part that the text delta was added to.


**Type**: integer

### `delta` (required)

The text delta that was added.


**Type**: string

## Example

```json
{
  "type": "response.output_text.delta",
  "item_id": "msg_123",
  "output_index": 0,
  "content_index": 0,
  "delta": "In"
}

```

