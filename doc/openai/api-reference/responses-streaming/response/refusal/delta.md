# response.refusal.delta

Emitted when there is a partial refusal text.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.refusal.delta` | The type of the event. Always `response.refusal.delta`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the output item that the refusal text is added to. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the refusal text is added to. <br>  |
| `content_index` | integer | Yes |  |  | The index of the content part that the refusal text is added to. <br>  |
| `delta` | string | Yes |  |  | The refusal text that is added. <br>  |

## Property Details

### `type` (required)

The type of the event. Always `response.refusal.delta`.


**Type**: string

**Allowed values**: `response.refusal.delta`

### `item_id` (required)

The ID of the output item that the refusal text is added to.


**Type**: string

### `output_index` (required)

The index of the output item that the refusal text is added to.


**Type**: integer

### `content_index` (required)

The index of the content part that the refusal text is added to.


**Type**: integer

### `delta` (required)

The refusal text that is added.


**Type**: string

## Example

```json
{
  "type": "response.refusal.delta",
  "item_id": "msg_123",
  "output_index": 0,
  "content_index": 0,
  "delta": "refusal text so far"
}

```

