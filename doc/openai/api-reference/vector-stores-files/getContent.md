# Retrieve vector store file content

`GET` `/vector_stores/{vector_store_id}/files/{file_id}/content`

Retrieve the parsed contents of a vector store file.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `vector_store_id` | string | Yes | The ID of the vector store. |
| `file_id` | string | Yes | The ID of the file within the vector store. |

## Responses

### 200 - OK

#### Content Type: `application/json`

**Type**: object (4 properties)

Represents the parsed content of a vector store file.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `vector_store.file_content.page` | The object type, which is always `vector_store.file_content.page` |
| `data` | array of object (2 properties) | Yes |  |  | Parsed content of the file. |
| `has_more` | boolean | Yes |  |  | Indicates if there are more content pages to fetch. |
| `next_page` | string | Yes |  |  | The token for the next page, if any. |


### Items in `data` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | No |  |  | The content type (currently only `"text"`) |
| `text` | string | No |  |  | The text content |
## Examples

### Request Examples

#### curl
```bash
curl \
https://api.openai.com/v1/vector_stores/vs_abc123/files/file-abc123/content \
-H "Authorization: Bearer $OPENAI_API_KEY"

```

### Response Example

```json
{
  "file_id": "file-abc123",
  "filename": "example.txt",
  "attributes": {"key": "value"},
  "content": [
    {"type": "text", "text": "..."},
    ...
  ]
}

```

