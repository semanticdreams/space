# response.reasoning_summary_text.delta

Emitted when a delta is added to a reasoning summary text.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.reasoning_summary_text.delta` | The type of the event. Always `response.reasoning_summary_text.delta`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the item this summary text delta is associated with. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item this summary text delta is associated with. <br>  |
| `summary_index` | integer | Yes |  |  | The index of the summary part within the reasoning summary. <br>  |
| `delta` | string | Yes |  |  | The text delta that was added to the summary. <br>  |

## Property Details

### `type` (required)

The type of the event. Always `response.reasoning_summary_text.delta`.


**Type**: string

**Allowed values**: `response.reasoning_summary_text.delta`

### `item_id` (required)

The ID of the item this summary text delta is associated with.


**Type**: string

### `output_index` (required)

The index of the output item this summary text delta is associated with.


**Type**: integer

### `summary_index` (required)

The index of the summary part within the reasoning summary.


**Type**: integer

### `delta` (required)

The text delta that was added to the summary.


**Type**: string

## Example

```json
{
  "type": "response.reasoning_summary_text.delta",
  "item_id": "rs_6806bfca0b2481918a5748308061a2600d3ce51bdffd5476",
  "output_index": 0,
  "summary_index": 0,
  "delta": "**Respond"
}

```

