# Search vector store

`POST` `/vector_stores/{vector_store_id}/search`

Search a vector store for relevant chunks based on a query and file attributes filter.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `vector_store_id` | string | Yes | The ID of the vector store to search. |

## Request Body

### Content Type: `application/json`

**Type**: object (5 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `query` | oneOf: string | array of string | Yes |  |  | A query string for a search |
| `rewrite_query` | boolean | No | `false` |  | Whether to rewrite the natural language query for vector search. |
| `max_num_results` | integer | No | `10` |  | The maximum number of results to return. This number should be between 1 and 50 inclusive. |
| `filters` | oneOf: object (3 properties) | object (2 properties) | No |  |  | A filter to apply based on file attributes. |
| `ranking_options` | object (2 properties) | No |  |  | Ranking options for search. |
## Responses

### 200 - OK

#### Content Type: `application/json`

**Type**: object (5 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `vector_store.search_results.page` | The object type, which is always `vector_store.search_results.page` |
| `search_query` | array of string | Yes |  |  |  |
| `data` | array of object (5 properties) | Yes |  |  | The list of search result items. |
| `has_more` | boolean | Yes |  |  | Indicates if there are more results to fetch. |
| `next_page` | string | Yes |  |  | The token for the next page, if any. |


### Items in `search_query` array

Each item is of type `string` - The query used for this search.



### Items in `data` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `file_id` | string | Yes |  |  | The ID of the vector store file. |
| `filename` | string | Yes |  |  | The name of the vector store file. |
| `score` | number | Yes |  |  | The similarity score for the result. |
| `attributes` | map | Yes |  |  | Set of 16 key-value pairs that can be attached to an object. This can be  <br> useful for storing additional information about the object in a structured  <br> format, and querying for objects via API or the dashboard. Keys are strings  <br> with a maximum length of 64 characters. Values are strings with a maximum  <br> length of 512 characters, booleans, or numbers. <br>  |
|   ↳ (additional properties) | oneOf: string | number | boolean | - | - | - | Additional properties of this object |
| `content` | array of object (2 properties) | Yes |  |  | Content chunks from the file. |


### Items in `content` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `text` | The type of content. |
| `text` | string | Yes |  |  | The text content returned from search. |
## Examples

### Request Examples

#### curl
```bash
curl -X POST \
https://api.openai.com/v1/vector_stores/vs_abc123/search \
-H "Authorization: Bearer $OPENAI_API_KEY" \
-H "Content-Type: application/json" \
-d '{"query": "What is the return policy?", "filters": {...}}'

```

### Response Example

```json
{
  "object": "vector_store.search_results.page",
  "search_query": "What is the return policy?",
  "data": [
    {
      "file_id": "file_123",
      "filename": "document.pdf",
      "score": 0.95,
      "attributes": {
        "author": "John Doe",
        "date": "2023-01-01"
      },
      "content": [
        {
          "type": "text",
          "text": "Relevant chunk"
        }
      ]
    },
    {
      "file_id": "file_456",
      "filename": "notes.txt",
      "score": 0.89,
      "attributes": {
        "author": "Jane Smith",
        "date": "2023-01-02"
      },
      "content": [
        {
          "type": "text",
          "text": "Sample text content from the vector store."
        }
      ]
    }
  ],
  "has_more": false,
  "next_page": null
}

```

