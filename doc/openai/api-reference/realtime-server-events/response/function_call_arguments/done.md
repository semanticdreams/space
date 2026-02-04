# response.function_call_arguments.done

Returned when the model-generated function call arguments are done streaming.
Also emitted when a Response is interrupted, incomplete, or cancelled.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `response.function_call_arguments.done` | The event type, must be `response.function_call_arguments.done`. <br>  |
| `response_id` | string | Yes |  |  | The ID of the response. |
| `item_id` | string | Yes |  |  | The ID of the function call item. |
| `output_index` | integer | Yes |  |  | The index of the output item in the response. |
| `call_id` | string | Yes |  |  | The ID of the function call. |
| `arguments` | string | Yes |  |  | The final arguments as a JSON string. |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be `response.function_call_arguments.done`.


**Type**: string

**Allowed values**: `response.function_call_arguments.done`

### `response_id` (required)

The ID of the response.

**Type**: string

### `item_id` (required)

The ID of the function call item.

**Type**: string

### `output_index` (required)

The index of the output item in the response.

**Type**: integer

### `call_id` (required)

The ID of the function call.

**Type**: string

### `arguments` (required)

The final arguments as a JSON string.

**Type**: string

## Example

```json
{
    "event_id": "event_5556",
    "type": "response.function_call_arguments.done",
    "response_id": "resp_002",
    "item_id": "fc_001",
    "output_index": 0,
    "call_id": "call_001",
    "arguments": "{\"location\": \"San Francisco\"}"
}

```

