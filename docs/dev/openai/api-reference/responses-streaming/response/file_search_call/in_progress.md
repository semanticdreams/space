# response.file_search_call.in_progress

Emitted when a file search call is initiated.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.file_search_call.in_progress` | The type of the event. Always `response.file_search_call.in_progress`. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the file search call is initiated. <br>  |
| `item_id` | string | Yes |  |  | The ID of the output item that the file search call is initiated. <br>  |

## Property Details

### `type` (required)

The type of the event. Always `response.file_search_call.in_progress`.


**Type**: string

**Allowed values**: `response.file_search_call.in_progress`

### `output_index` (required)

The index of the output item that the file search call is initiated.


**Type**: integer

### `item_id` (required)

The ID of the output item that the file search call is initiated.


**Type**: string

## Example

```json
{
  "type": "response.file_search_call.in_progress",
  "output_index": 0,
  "item_id": "fs_123",
}

```

