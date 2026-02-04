# response.refusal.done

Emitted when refusal text is finalized.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.refusal.done` | The type of the event. Always `response.refusal.done`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the output item that the refusal text is finalized. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the refusal text is finalized. <br>  |
| `content_index` | integer | Yes |  |  | The index of the content part that the refusal text is finalized. <br>  |
| `refusal` | string | Yes |  |  | The refusal text that is finalized. <br>  |

## Property Details

### `type` (required)

The type of the event. Always `response.refusal.done`.


**Type**: string

**Allowed values**: `response.refusal.done`

### `item_id` (required)

The ID of the output item that the refusal text is finalized.


**Type**: string

### `output_index` (required)

The index of the output item that the refusal text is finalized.


**Type**: integer

### `content_index` (required)

The index of the content part that the refusal text is finalized.


**Type**: integer

### `refusal` (required)

The refusal text that is finalized.


**Type**: string

## Example

```json
{
  "type": "response.refusal.done",
  "item_id": "item-abc",
  "output_index": 1,
  "content_index": 2,
  "refusal": "final refusal text"
}

```

