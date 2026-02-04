# List evals

`GET` `/evals`

List evaluations for a project.


## Parameters

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `after` | string | No | Identifier for the last eval from the previous pagination request. |
| `limit` | integer | No | Number of evals to retrieve. |
| `order` | string | No | Sort order for evals by timestamp. Use `asc` for ascending order or `desc` for descending order. |
| `order_by` | string | No | Evals can be ordered by creation time or last updated time. Use <br> `created_at` for creation time or `updated_at` for last updated time. <br>  |

## Responses

### 200 - A list of evals

#### Content Type: `application/json`

#### EvalList

**Type**: object (5 properties)

An object representing a list of evals.


#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes | `list` | `list` | The type of this object. It is always set to "list". <br>  |
| `data` | array of object (7 properties) | Yes |  |  | An array of eval objects. <br>  |
| `first_id` | string | Yes |  |  | The identifier of the first eval in the data array. |
| `last_id` | string | Yes |  |  | The identifier of the last eval in the data array. |
| `has_more` | boolean | Yes |  |  | Indicates whether there are more evals available. |


### Items in `data` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes | `eval` | `eval` | The object type. |
| `id` | string | Yes |  |  | Unique identifier for the evaluation. |
| `name` | string | Yes |  |  | The name of the evaluation. |
| `data_source_config` | object | Yes |  |  | Configuration of data sources used in runs of the evaluation. |
| `testing_criteria` | array of oneOf: object (6 properties) | object (5 properties) | object (6 properties) | object (5 properties) | object (7 properties) | Yes | `eval` |  | A list of testing criteria. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the eval was created. |
| `metadata` | map | Yes |  |  | Set of 16 key-value pairs that can be attached to an object. This can be <br> useful for storing additional information about the object in a structured <br> format, and querying for objects via API or the dashboard.  <br>  <br> Keys are strings with a maximum length of 64 characters. Values are strings <br> with a maximum length of 512 characters. <br>  |
|   ↳ (additional properties) | string | - | - | - | Additional properties of this object |
**Example:**

```json
{
  "object": "list",
  "data": [
    {
      "object": "eval",
      "id": "eval_67abd54d9b0081909a86353f6fb9317a",
      "data_source_config": {
        "type": "custom",
        "schema": {
          "type": "object",
          "properties": {
            "item": {
              "type": "object",
              "properties": {
                "input": {
                  "type": "string"
                },
                "ground_truth": {
                  "type": "string"
                }
              },
              "required": [
                "input",
                "ground_truth"
              ]
            }
          },
          "required": [
            "item"
          ]
        }
      },
      "testing_criteria": [
        {
          "name": "String check",
          "id": "String check-2eaf2d8d-d649-4335-8148-9535a7ca73c2",
          "type": "string_check",
          "input": "{{item.input}}",
          "reference": "{{item.ground_truth}}",
          "operation": "eq"
        }
      ],
      "name": "External Data Eval",
      "created_at": 1739314509,
      "metadata": {},
    }
  ],
  "first_id": "eval_67abd54d9b0081909a86353f6fb9317a",
  "last_id": "eval_67abd54d9b0081909a86353f6fb9317a",
  "has_more": true
}

```

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/evals?limit=1 \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json"

```

### Response Example

```json
{
  "object": "list",
  "data": [
    {
      "id": "eval_67abd54d9b0081909a86353f6fb9317a",
      "object": "eval",
      "data_source_config": {
        "type": "stored_completions",
        "metadata": {
          "usecase": "push_notifications_summarizer"
        },
        "schema": {
          "type": "object",
          "properties": {
            "item": {
              "type": "object"
            },
            "sample": {
              "type": "object"
            }
          },
          "required": [
            "item",
            "sample"
          ]
        }
      },
      "testing_criteria": [
        {
          "name": "Push Notification Summary Grader",
          "id": "Push Notification Summary Grader-9b876f24-4762-4be9-aff4-db7a9b31c673",
          "type": "label_model",
          "model": "o3-mini",
          "input": [
            {
              "type": "message",
              "role": "developer",
              "content": {
                "type": "input_text",
                "text": "\nLabel the following push notification summary as either correct or incorrect.\nThe push notification and the summary will be provided below.\nA good push notificiation summary is concise and snappy.\nIf it is good, then label it as correct, if not, then incorrect.\n"
              }
            },
            {
              "type": "message",
              "role": "user",
              "content": {
                "type": "input_text",
                "text": "\nPush notifications: {{item.input}}\nSummary: {{sample.output_text}}\n"
              }
            }
          ],
          "passing_labels": [
            "correct"
          ],
          "labels": [
            "correct",
            "incorrect"
          ],
          "sampling_params": null
        }
      ],
      "name": "Push Notification Summary Grader",
      "created_at": 1739314509,
      "metadata": {
        "description": "A stored completions eval for push notification summaries"
      }
    }
  ],
  "first_id": "eval_67abd54d9b0081909a86353f6fb9317a",
  "last_id": "eval_67aa884cf6688190b58f657d4441c8b7",
  "has_more": true
}

```

