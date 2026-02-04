# response.function_call_arguments.delta

Emitted when there is a partial function-call arguments delta.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.function_call_arguments.delta` | The type of the event. Always `response.function_call_arguments.delta`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the output item that the function-call arguments delta is added to. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the function-call arguments delta is added to. <br>  |
| `delta` | string | Yes |  |  | The function-call arguments delta that is added. <br>  |

## Property Details

### `type` (required)

The type of the event. Always `response.function_call_arguments.delta`.


**Type**: string

**Allowed values**: `response.function_call_arguments.delta`

### `item_id` (required)

The ID of the output item that the function-call arguments delta is added to.


**Type**: string

### `output_index` (required)

The index of the output item that the function-call arguments delta is added to.


**Type**: integer

### `delta` (required)

The function-call arguments delta that is added.


**Type**: string

## Example

```json
{
  "type": "response.function_call_arguments.delta",
  "item_id": "item-abc",
  "output_index": 0,
  "delta": "{ \"arg\":"
}

```

