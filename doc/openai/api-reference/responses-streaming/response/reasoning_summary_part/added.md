# response.reasoning_summary_part.added

Emitted when a new reasoning summary part is added.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.reasoning_summary_part.added` | The type of the event. Always `response.reasoning_summary_part.added`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the item this summary part is associated with. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item this summary part is associated with. <br>  |
| `summary_index` | integer | Yes |  |  | The index of the summary part within the reasoning summary. <br>  |
| `part` | object (2 properties) | Yes |  |  | The summary part that was added. <br>  |

## Property Details

### `type` (required)

The type of the event. Always `response.reasoning_summary_part.added`.


**Type**: string

**Allowed values**: `response.reasoning_summary_part.added`

### `item_id` (required)

The ID of the item this summary part is associated with.


**Type**: string

### `output_index` (required)

The index of the output item this summary part is associated with.


**Type**: integer

### `summary_index` (required)

The index of the summary part within the reasoning summary.


**Type**: integer

### `part` (required)

The summary part that was added.


**Type**: object (2 properties)

**Nested Properties**:

* `type`, `text`

## Example

```json
{
  "type": "response.reasoning_summary_part.added",
  "item_id": "rs_6806bfca0b2481918a5748308061a2600d3ce51bdffd5476",
  "output_index": 0,
  "summary_index": 0,
  "part": {
    "type": "summary_text",
    "text": ""
  }
}

```

