# response.file_search_call.searching

Emitted when a file search is currently searching.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.file_search_call.searching` | The type of the event. Always `response.file_search_call.searching`. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the file search call is searching. <br>  |
| `item_id` | string | Yes |  |  | The ID of the output item that the file search call is initiated. <br>  |

## Property Details

### `type` (required)

The type of the event. Always `response.file_search_call.searching`.


**Type**: string

**Allowed values**: `response.file_search_call.searching`

### `output_index` (required)

The index of the output item that the file search call is searching.


**Type**: integer

### `item_id` (required)

The ID of the output item that the file search call is initiated.


**Type**: string

## Example

```json
{
  "type": "response.file_search_call.searching",
  "output_index": 0,
  "item_id": "fs_123",
}

```

