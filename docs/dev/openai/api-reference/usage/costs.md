# Costs

`GET` `/organization/costs`

Get costs details for the organization.

## Parameters

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `start_time` | integer | Yes | Start time (Unix seconds) of the query time range, inclusive. |
| `end_time` | integer | No | End time (Unix seconds) of the query time range, exclusive. |
| `bucket_width` | string | No | Width of each time bucket in response. Currently only `1d` is supported, default to `1d`. |
| `project_ids` | array of string | No | Return only costs for these projects. |
| `group_by` | array of string | No | Group the costs by the specified fields. Support fields include `project_id`, `line_item` and any combination of them. |
| `limit` | integer | No | A limit on the number of buckets to be returned. Limit can range between 1 and 180, and the default is 7. <br>  |
| `page` | string | No | A cursor for use in pagination. Corresponding to the `next_page` field from the previous response. |

## Responses

### 200 - Costs data retrieved successfully.

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
curl "https://api.openai.com/v1/organization/costs?start_time=1730419200&limit=1" \
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
                    "object": "organization.costs.result",
                    "amount": {
                        "value": 0.06,
                        "currency": "usd"
                    },
                    "line_item": null,
                    "project_id": null
                }
            ]
        }
    ],
    "has_more": false,
    "next_page": null
}

```

