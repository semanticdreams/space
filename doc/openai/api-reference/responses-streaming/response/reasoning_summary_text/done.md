# response.reasoning_summary_text.done

Emitted when a reasoning summary text is completed.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.reasoning_summary_text.done` | The type of the event. Always `response.reasoning_summary_text.done`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the item this summary text is associated with. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item this summary text is associated with. <br>  |
| `summary_index` | integer | Yes |  |  | The index of the summary part within the reasoning summary. <br>  |
| `text` | string | Yes |  |  | The full text of the completed reasoning summary. <br>  |

## Property Details

### `type` (required)

The type of the event. Always `response.reasoning_summary_text.done`.


**Type**: string

**Allowed values**: `response.reasoning_summary_text.done`

### `item_id` (required)

The ID of the item this summary text is associated with.


**Type**: string

### `output_index` (required)

The index of the output item this summary text is associated with.


**Type**: integer

### `summary_index` (required)

The index of the summary part within the reasoning summary.


**Type**: integer

### `text` (required)

The full text of the completed reasoning summary.


**Type**: string

## Example

```json
{
  "type": "response.reasoning_summary_text.done",
  "item_id": "rs_6806bfca0b2481918a5748308061a2600d3ce51bdffd5476",
  "output_index": 0,
  "summary_index": 0,
  "text": "**Responding to a greeting**\n\nThe user just said, \"Hello!\" So, it seems I need to engage. I'll greet them back and offer help since they're looking to chat. I could say something like, \"Hello! How can I assist you today?\" That feels friendly and open. They didn't ask a specific question, so this approach will work well for starting a conversation. Let's see where it goes from there!"
}

```

