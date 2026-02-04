# response.output_text.done

Emitted when text content is finalized.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.output_text.done` | The type of the event. Always `response.output_text.done`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the output item that the text content is finalized. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the text content is finalized. <br>  |
| `content_index` | integer | Yes |  |  | The index of the content part that the text content is finalized. <br>  |
| `text` | string | Yes |  |  | The text content that is finalized. <br>  |

## Property Details

### `type` (required)

The type of the event. Always `response.output_text.done`.


**Type**: string

**Allowed values**: `response.output_text.done`

### `item_id` (required)

The ID of the output item that the text content is finalized.


**Type**: string

### `output_index` (required)

The index of the output item that the text content is finalized.


**Type**: integer

### `content_index` (required)

The index of the content part that the text content is finalized.


**Type**: integer

### `text` (required)

The text content that is finalized.


**Type**: string

## Example

```json
{
  "type": "response.output_text.done",
  "item_id": "msg_123",
  "output_index": 0,
  "content_index": 0,
  "text": "In a shimmering forest under a sky full of stars, a lonely unicorn named Lila discovered a hidden pond that glowed with moonlight. Every night, she would leave sparkling, magical flowers by the water's edge, hoping to share her beauty with others. One enchanting evening, she woke to find a group of friendly animals gathered around, eager to be friends and share in her magic."
}

```

