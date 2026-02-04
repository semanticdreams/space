# response.content_part.done

Emitted when a content part is done.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.content_part.done` | The type of the event. Always `response.content_part.done`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the output item that the content part was added to. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the content part was added to. <br>  |
| `content_index` | integer | Yes |  |  | The index of the content part that is done. <br>  |
| `part` | oneOf: object (3 properties) | object (2 properties) | Yes |  |  | The content part that is done. <br>  |

## Property Details

### `type` (required)

The type of the event. Always `response.content_part.done`.


**Type**: string

**Allowed values**: `response.content_part.done`

### `item_id` (required)

The ID of the output item that the content part was added to.


**Type**: string

### `output_index` (required)

The index of the output item that the content part was added to.


**Type**: integer

### `content_index` (required)

The index of the content part that is done.


**Type**: integer

### `part` (required)

The content part that is done.


**Type**: oneOf: object (3 properties) | object (2 properties)

## Example

```json
{
  "type": "response.content_part.done",
  "item_id": "msg_123",
  "output_index": 0,
  "content_index": 0,
  "part": {
    "type": "output_text",
    "text": "In a shimmering forest under a sky full of stars, a lonely unicorn named Lila discovered a hidden pond that glowed with moonlight. Every night, she would leave sparkling, magical flowers by the water's edge, hoping to share her beauty with others. One enchanting evening, she woke to find a group of friendly animals gathered around, eager to be friends and share in her magic.",
    "annotations": []
  }
}

```

