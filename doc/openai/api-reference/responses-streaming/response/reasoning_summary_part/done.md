# response.reasoning_summary_part.done

Emitted when a reasoning summary part is completed.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.reasoning_summary_part.done` | The type of the event. Always `response.reasoning_summary_part.done`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the item this summary part is associated with. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item this summary part is associated with. <br>  |
| `summary_index` | integer | Yes |  |  | The index of the summary part within the reasoning summary. <br>  |
| `part` | object (2 properties) | Yes |  |  | The completed summary part. <br>  |

## Property Details

### `type` (required)

The type of the event. Always `response.reasoning_summary_part.done`.


**Type**: string

**Allowed values**: `response.reasoning_summary_part.done`

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

The completed summary part.


**Type**: object (2 properties)

**Nested Properties**:

* `type`, `text`

## Example

```json
{
  "type": "response.reasoning_summary_part.done",
  "item_id": "rs_6806bfca0b2481918a5748308061a2600d3ce51bdffd5476",
  "output_index": 0,
  "summary_index": 0,
  "part": {
    "type": "summary_text",
    "text": "**Responding to a greeting**\n\nThe user just said, \"Hello!\" So, it seems I need to engage. I'll greet them back and offer help since they're looking to chat. I could say something like, \"Hello! How can I assist you today?\" That feels friendly and open. They didn't ask a specific question, so this approach will work well for starting a conversation. Let's see where it goes from there!"
  }
}

```

