# response.output_text.annotation.added

Emitted when a text annotation is added.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.output_text.annotation.added` | The type of the event. Always `response.output_text.annotation.added`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the output item that the text annotation was added to. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the text annotation was added to. <br>  |
| `content_index` | integer | Yes |  |  | The index of the content part that the text annotation was added to. <br>  |
| `annotation_index` | integer | Yes |  |  | The index of the annotation that was added. <br>  |
| `annotation` | oneOf: object (3 properties) | object (5 properties) | object (3 properties) | Yes |  |  |  |

## Property Details

### `type` (required)

The type of the event. Always `response.output_text.annotation.added`.


**Type**: string

**Allowed values**: `response.output_text.annotation.added`

### `item_id` (required)

The ID of the output item that the text annotation was added to.


**Type**: string

### `output_index` (required)

The index of the output item that the text annotation was added to.


**Type**: integer

### `content_index` (required)

The index of the content part that the text annotation was added to.


**Type**: integer

### `annotation_index` (required)

The index of the annotation that was added.


**Type**: integer

### `annotation` (required)

**Type**: oneOf: object (3 properties) | object (5 properties) | object (3 properties)

## Example

```json
{
  "type": "response.output_text.annotation.added",
  "item_id": "msg_abc123",
  "output_index": 1,
  "content_index": 0,
  "annotation_index": 0,
  "annotation": {
    "type": "file_citation",
    "index": 390,
    "file_id": "file-4wDz5b167pAf72nx1h9eiN",
    "filename": "dragons.pdf"
  }
}

```

