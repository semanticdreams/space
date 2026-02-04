# Vector stores

`GET` `/organization/usage/vector_stores`

Get vector stores usage details for the organization.

## Parameters

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `start_time` | integer | Yes | Start time (Unix seconds) of the query time range, inclusive. |
| `end_time` | integer | No | End time (Unix seconds) of the query time range, exclusive. |
| `bucket_width` | string | No | Width of each time bucket in response. Currently `1m`, `1h` and `1d` are supported, default to `1d`. |
| `project_ids` | array of string | No | Return only usage for these projects. |
| `group_by` | array of string | No | Group the usage data by the specified fields. Support fields include `project_id`. |
| `limit` | integer | No | Specifies the number of buckets to return. <br> - `bucket_width=1d`: default: 7, max: 31 <br> - `bucket_width=1h`: default: 24, max: 168 <br> - `bucket_width=1m`: default: 60, max: 1440 <br>  |
| `page` | string | No | A cursor for use in pagination. Corresponding to the `next_page` field from the previous response. |

## Responses

### 200 - Usage data retrieved successfully.

#### Content Type: `application/json`

**Type**: object (4 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `page` |  |
| `data` | array of object (4 properties) | Yes |  |  |  |
| `has_more` | boolean | Yes |  |  |  |
| `next_page` | string | Yes |  |  |  |


### Items in `data` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `bucket` |  |
| `start_time` | integer | Yes |  |  |  |
| `end_time` | integer | Yes |  |  |  |
| `result` | array of oneOf: object (12 properties) | object (7 properties) | object (7 properties) | object (9 properties) | object (7 properties) | object (7 properties) | object (3 properties) | object (3 properties) | object (4 properties) | Yes |  |  |  |
## Examples

### Request Examples

#### curl
```bash
curl "https://api.openai.com/v1/organization/usage/vector_stores?start_time=1730419200&limit=1" \
-H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
-H "Content-Type: application/json"

```

### Response Example

```json
{
    "object": "page",
    "data": [
        {
            "object": "bucket",
            "start_time": 1730419200,
            "end_time": 1730505600,
            "results": [
                {
                    "object": "organization.usage.vector_stores.result",
                    "usage_bytes": 1024,
                    "project_id": null
                }
            ]
        }
    ],
    "has_more": false,
    "next_page": null
}

```

