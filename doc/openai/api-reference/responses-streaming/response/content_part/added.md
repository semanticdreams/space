# response.content_part.added

Emitted when a new content part is added.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.content_part.added` | The type of the event. Always `response.content_part.added`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the output item that the content part was added to. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the content part was added to. <br>  |
| `content_index` | integer | Yes |  |  | The index of the content part that was added. <br>  |
| `part` | oneOf: object (3 properties) | object (2 properties) | Yes |  |  | The content part that was added. <br>  |

## Property Details

### `type` (required)

The type of the event. Always `response.content_part.added`.


**Type**: string

**Allowed values**: `response.content_part.added`

### `item_id` (required)

The ID of the output item that the content part was added to.


**Type**: string

### `output_index` (required)

The index of the output item that the content part was added to.


**Type**: integer

### `content_index` (required)

The index of the content part that was added.


**Type**: integer

### `part` (required)

The content part that was added.


**Type**: oneOf: object (3 properties) | object (2 properties)

## Example

```json
{
  "type": "response.content_part.added",
  "item_id": "msg_123",
  "output_index": 0,
  "content_index": 0,
  "part": {
    "type": "output_text",
    "text": "",
    "annotations": []
  }
}

```

