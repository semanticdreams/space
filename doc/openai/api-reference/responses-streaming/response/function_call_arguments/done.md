# response.function_call_arguments.done

Emitted when function-call arguments are finalized.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.function_call_arguments.done` |  |
| `item_id` | string | Yes |  |  | The ID of the item. |
| `output_index` | integer | Yes |  |  | The index of the output item. |
| `arguments` | string | Yes |  |  | The function-call arguments. |

## Property Details

### `type` (required)

**Type**: string

**Allowed values**: `response.function_call_arguments.done`

### `item_id` (required)

The ID of the item.

**Type**: string

### `output_index` (required)

The index of the output item.

**Type**: integer

### `arguments` (required)

The function-call arguments.

**Type**: string

## Example

```json
{
  "type": "response.function_call_arguments.done",
  "item_id": "item-abc",
  "output_index": 1,
  "arguments": "{ \"arg\": 123 }"
}

```

