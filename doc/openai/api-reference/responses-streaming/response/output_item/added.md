# response.output_item.added

Emitted when a new output item is added.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.output_item.added` | The type of the event. Always `response.output_item.added`. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that was added. <br>  |
| `item` | anyOf: object (5 properties) | object (5 properties) | object (6 properties) | object (3 properties) | object (6 properties) | object (5 properties) | Yes |  |  | The output item that was added. <br>  |

## Property Details

### `type` (required)

The type of the event. Always `response.output_item.added`.


**Type**: string

**Allowed values**: `response.output_item.added`

### `output_index` (required)

The index of the output item that was added.


**Type**: integer

### `item` (required)

The output item that was added.


**Type**: anyOf: object (5 properties) | object (5 properties) | object (6 properties) | object (3 properties) | object (6 properties) | object (5 properties)

## Example

```json
{
  "type": "response.output_item.added",
  "output_index": 0,
  "item": {
    "id": "msg_123",
    "status": "in_progress",
    "type": "message",
    "role": "assistant",
    "content": []
  }
}

```

