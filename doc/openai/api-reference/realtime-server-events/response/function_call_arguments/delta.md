# response.function_call_arguments.delta

Returned when the model-generated function call arguments are updated.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `response.function_call_arguments.delta` | The event type, must be `response.function_call_arguments.delta`. <br>  |
| `response_id` | string | Yes |  |  | The ID of the response. |
| `item_id` | string | Yes |  |  | The ID of the function call item. |
| `output_index` | integer | Yes |  |  | The index of the output item in the response. |
| `call_id` | string | Yes |  |  | The ID of the function call. |
| `delta` | string | Yes |  |  | The arguments delta as a JSON string. |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be `response.function_call_arguments.delta`.


**Type**: string

**Allowed values**: `response.function_call_arguments.delta`

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

### `delta` (required)

The arguments delta as a JSON string.

**Type**: string

## Example

```json
{
    "event_id": "event_5354",
    "type": "response.function_call_arguments.delta",
    "response_id": "resp_002",
    "item_id": "fc_001",
    "output_index": 0,
    "call_id": "call_001",
    "delta": "{\"location\": \"San\""
}

```

