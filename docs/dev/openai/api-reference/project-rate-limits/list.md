# List project rate limits

`GET` `/organization/projects/{project_id}/rate_limits`

Returns the rate limits per model for a project.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `project_id` | string | Yes | The ID of the project. |

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `limit` | integer | No | A limit on the number of objects to be returned. The default is 100. <br>  |
| `after` | string | No | A cursor for use in pagination. `after` is an object ID that defines your place in the list. For instance, if you make a list request and receive 100 objects, ending with obj_foo, your subsequent call can include after=obj_foo in order to fetch the next page of the list. <br>  |
| `before` | string | No | A cursor for use in pagination. `before` is an object ID that defines your place in the list. For instance, if you make a list request and receive 100 objects, beginning with obj_foo, your subsequent call can include before=obj_foo in order to fetch the previous page of the list. <br>  |

## Responses

### 200 - Project rate limits listed successfully.

#### Content Type: `application/json`

**Type**: object (5 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `list` |  |
| `data` | array of object (9 properties) | Yes |  |  |  |
| `first_id` | string | Yes |  |  |  |
| `last_id` | string | Yes |  |  |  |
| `has_more` | boolean | Yes |  |  |  |


### Items in `data` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `project.rate_limit` | The object type, which is always `project.rate_limit` |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints. |
| `model` | string | Yes |  |  | The model this rate limit applies to. |
| `max_requests_per_1_minute` | integer | Yes |  |  | The maximum requests per minute. |
| `max_tokens_per_1_minute` | integer | Yes |  |  | The maximum tokens per minute. |
| `max_images_per_1_minute` | integer | No |  |  | The maximum images per minute. Only present for relevant models. |
| `max_audio_megabytes_per_1_minute` | integer | No |  |  | The maximum audio megabytes per minute. Only present for relevant models. |
| `max_requests_per_1_day` | integer | No |  |  | The maximum requests per day. Only present for relevant models. |
| `batch_1_day_max_input_tokens` | integer | No |  |  | The maximum batch input tokens per day. Only present for relevant models. |
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/organization/projects/proj_abc/rate_limits?after=rl_xxx&limit=20 \
  -H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
  -H "Content-Type: application/json"

```

### Response Example

```json
{
    "object": "list",
    "data": [
        {
          "object": "project.rate_limit",
          "id": "rl-ada",
          "model": "ada",
          "max_requests_per_1_minute": 600,
          "max_tokens_per_1_minute": 150000,
          "max_images_per_1_minute": 10
        }
    ],
    "first_id": "rl-ada",
    "last_id": "rl-ada",
    "has_more": false
}

```

