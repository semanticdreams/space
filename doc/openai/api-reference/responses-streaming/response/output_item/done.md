# response.output_item.done

Emitted when an output item is marked done.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.output_item.done` | The type of the event. Always `response.output_item.done`. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that was marked done. <br>  |
| `item` | anyOf: object (5 properties) | object (5 properties) | object (6 properties) | object (3 properties) | object (6 properties) | object (5 properties) | Yes |  |  | The output item that was marked done. <br>  |

## Property Details

### `type` (required)

The type of the event. Always `response.output_item.done`.


**Type**: string

**Allowed values**: `response.output_item.done`

### `output_index` (required)

The index of the output item that was marked done.


**Type**: integer

### `item` (required)

The output item that was marked done.


**Type**: anyOf: object (5 properties) | object (5 properties) | object (6 properties) | object (3 properties) | object (6 properties) | object (5 properties)

## Example

```json
{
  "type": "response.output_item.done",
  "output_index": 0,
  "item": {
    "id": "msg_123",
    "status": "completed",
    "type": "message",
    "role": "assistant",
    "content": [
      {
        "type": "output_text",
        "text": "In a shimmering forest under a sky full of stars, a lonely unicorn named Lila discovered a hidden pond that glowed with moonlight. Every night, she would leave sparkling, magical flowers by the water's edge, hoping to share her beauty with others. One enchanting evening, she woke to find a group of friendly animals gathered around, eager to be friends and share in her magic.",
        "annotations": []
      }
    ]
  }
}

```

