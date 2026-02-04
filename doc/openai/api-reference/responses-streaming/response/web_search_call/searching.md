# response.web_search_call.searching

Emitted when a web search call is executing.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.web_search_call.searching` | The type of the event. Always `response.web_search_call.searching`. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the web search call is associated with. <br>  |
| `item_id` | string | Yes |  |  | Unique ID for the output item associated with the web search call. <br>  |

## Property Details

### `type` (required)

The type of the event. Always `response.web_search_call.searching`.


**Type**: string

**Allowed values**: `response.web_search_call.searching`

### `output_index` (required)

The index of the output item that the web search call is associated with.


**Type**: integer

### `item_id` (required)

Unique ID for the output item associated with the web search call.


**Type**: string

## Example

```json
{
  "type": "response.web_search_call.searching",
  "output_index": 0,
  "item_id": "ws_123",
}

```

