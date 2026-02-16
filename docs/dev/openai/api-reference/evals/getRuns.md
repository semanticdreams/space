# Get eval runs

`GET` `/evals/{eval_id}/runs`

Get a list of runs for an evaluation.


## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `eval_id` | string | Yes | The ID of the evaluation to retrieve runs for. |

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `after` | string | No | Identifier for the last run from the previous pagination request. |
| `limit` | integer | No | Number of runs to retrieve. |
| `order` | string | No | Sort order for runs by timestamp. Use `asc` for ascending order or `desc` for descending order. Defaults to `asc`. |
| `status` | string | No | Filter runs by status. One of `queued` | `in_progress` | `failed` | `completed` | `canceled`. |

## Responses

### 200 - A list of runs for the evaluation

#### Content Type: `application/json`

#### EvalRunList

**Type**: object (5 properties)

An object representing a list of runs for an evaluation.


#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes | `list` | `list` | The type of this object. It is always set to "list". <br>  |
| `data` | array of object (14 properties) | Yes |  |  | An array of eval run objects. <br>  |
| `first_id` | string | Yes |  |  | The identifier of the first eval run in the data array. |
| `last_id` | string | Yes |  |  | The identifier of the last eval run in the data array. |
| `has_more` | boolean | Yes |  |  | Indicates whether there are more evals available. |


### Items in `data` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes | `eval.run` | `eval.run` | The type of the object. Always "eval.run". |
| `id` | string | Yes |  |  | Unique identifier for the evaluation run. |
| `eval_id` | string | Yes |  |  | The identifier of the associated evaluation. |
| `status` | string | Yes |  |  | The status of the evaluation run. |
| `model` | string | Yes |  |  | The model that is evaluated, if applicable. |
| `name` | string | Yes |  |  | The name of the evaluation run. |
| `created_at` | integer | Yes |  |  | Unix timestamp (in seconds) when the evaluation run was created. |
| `report_url` | string | Yes |  |  | The URL to the rendered evaluation run report on the UI dashboard. |
| `result_counts` | object (4 properties) | Yes |  |  | Counters summarizing the outcomes of the evaluation run. |
|   ↳ `failed` | integer | Yes |  |  | Number of output items that failed to pass the evaluation. |
|   ↳ `passed` | integer | Yes |  |  | Number of output items that passed the evaluation. |
| `per_model_usage` | array of object (6 properties) | Yes |  |  | Usage statistics for each model during the evaluation run. |
| `per_testing_criteria_results` | array of object (3 properties) | Yes |  |  | Results per testing criteria applied during the evaluation run. |
| `data_source` | object | Yes |  |  | Information about the run's data source. |
| `metadata` | map | Yes |  |  | Set of 16 key-value pairs that can be attached to an object. This can be <br> useful for storing additional information about the object in a structured <br> format, and querying for objects via API or the dashboard.  <br>  <br> Keys are strings with a maximum length of 64 characters. Values are strings <br> with a maximum length of 512 characters. <br>  |
|   ↳ (additional properties) | string | - | - | - | Additional properties of this object |
| `error` | object (2 properties) | Yes |  |  | An object representing an error response from the Eval API. <br>  |


### Items in `per_model_usage` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `model_name` | string | Yes |  |  | The name of the model. |
| `invocation_count` | integer | Yes |  |  | The number of invocations. |
| `prompt_tokens` | integer | Yes |  |  | The number of prompt tokens used. |
| `completion_tokens` | integer | Yes |  |  | The number of completion tokens generated. |
| `total_tokens` | integer | Yes |  |  | The total number of tokens used. |
| `cached_tokens` | integer | Yes |  |  | The number of tokens retrieved from cache. |


### Items in `per_testing_criteria_results` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `testing_criteria` | string | Yes |  |  | A description of the testing criteria. |
| `passed` | integer | Yes |  |  | Number of tests passed for this criteria. |
| `failed` | integer | Yes |  |  | Number of tests failed for this criteria. |
**Example:**

```json
{
  "object": "list",
  "data": [
    {
      "object": "eval.run",
      "id": "evalrun_67b7fbdad46c819092f6fe7a14189620",
      "eval_id": "eval_67b7fa9a81a88190ab4aa417e397ea21",
      "report_url": "https://platform.openai.com/evaluations/eval_67b7fa9a81a88190ab4aa417e397ea21?run_id=evalrun_67b7fbdad46c819092f6fe7a14189620",
      "status": "completed",
      "model": "o3-mini",
      "name": "Academic Assistant",
      "created_at": 1740110812,
      "result_counts": {
        "total": 171,
        "errored": 0,
        "failed": 80,
        "passed": 91
      },
      "per_model_usage": null,
      "per_testing_criteria_results": [
        {
          "testing_criteria": "String check grader",
          "passed": 91,
          "failed": 80
        }
      ],
      "run_data_source": {
        "type": "completions",
        "template_messages": [
          {
            "type": "message",
            "role": "system",
            "content": {
              "type": "input_text",
              "text": "You are a helpful assistant."
            }
          },
          {
            "type": "message",
            "role": "user",
            "content": {
              "type": "input_text",
              "text": "Hello, can you help me with my homework?"
            }
          }
        ],
        "datasource_reference": null,
        "model": "o3-mini",
        "max_completion_tokens": null,
        "seed": null,
        "temperature": null,
        "top_p": null
      },
      "error": null,
      "metadata": {"test": "synthetics"}
    }
  ],
  "first_id": "evalrun_67abd54d60ec8190832b46859da808f7",
  "last_id": "evalrun_67abd54d60ec8190832b46859da808f7",
  "has_more": false
}

```

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/evals/egroup_67abd54d9b0081909a86353f6fb9317a/runs \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json"

```

### Response Example

```json
{
  "object": "list",
  "data": [
    {
      "object": "eval.run",
      "id": "evalrun_67e0c7d31560819090d60c0780591042",
      "eval_id": "eval_67e0c726d560819083f19a957c4c640b",
      "report_url": "https://platform.openai.com/evaluations/eval_67e0c726d560819083f19a957c4c640b",
      "status": "completed",
      "model": "o3-mini",
      "name": "bulk_with_negative_examples_o3-mini",
      "created_at": 1742784467,
      "result_counts": {
        "total": 1,
        "errored": 0,
        "failed": 0,
        "passed": 1
      },
      "per_model_usage": [
        {
          "model_name": "o3-mini",
          "invocation_count": 1,
          "prompt_tokens": 563,
          "completion_tokens": 874,
          "total_tokens": 1437,
          "cached_tokens": 0
        }
      ],
      "per_testing_criteria_results": [
        {
          "testing_criteria": "Push Notification Summary Grader-1808cd0b-eeec-4e0b-a519-337e79f4f5d1",
          "passed": 1,
          "failed": 0
        }
      ],
      "data_source": {
        "type": "completions",
        "source": {
          "type": "file_content",
          "content": [
            {
              "item": {
                "notifications": "\n- New message from Sarah: \"Can you call me later?\"\n- Your package has been delivered!\n- Flash sale: 20% off electronics for the next 2 hours!\n"
              }
            }
          ]
        },
        "input_messages": {
          "type": "template",
          "template": [
            {
              "type": "message",
              "role": "developer",
              "content": {
                "type": "input_text",
                "text": "\n\n\n\nYou are a helpful assistant that takes in an array of push notifications and returns a collapsed summary of them.\nThe push notification will be provided as follows:\n<push_notifications>\n...notificationlist...\n</push_notifications>\n\nYou should return just the summary and nothing else.\n\n\nYou should return a summary that is concise and snappy.\n\n\nHere is an example of a good summary:\n<push_notifications>\n- Traffic alert: Accident reported on Main Street.- Package out for delivery: Expected by 5 PM.- New friend suggestion: Connect with Emma.\n</push_notifications>\n<summary>\nTraffic alert, package expected by 5pm, suggestion for new friend (Emily).\n</summary>\n\n\nHere is an example of a bad summary:\n<push_notifications>\n- Traffic alert: Accident reported on Main Street.- Package out for delivery: Expected by 5 PM.- New friend suggestion: Connect with Emma.\n</push_notifications>\n<summary>\nTraffic alert reported on main street. You have a package that will arrive by 5pm, Emily is a new friend suggested for you.\n</summary>\n"
              }
            },
            {
              "type": "message",
              "role": "user",
              "content": {
                "type": "input_text",
                "text": "<push_notifications>{{item.notifications}}</push_notifications>"
              }
            }
          ]
        },
        "model": "o3-mini",
        "sampling_params": null
      },
      "error": null,
      "metadata": {}
    }
  ],
  "first_id": "evalrun_67e0c7d31560819090d60c0780591042",
  "last_id": "evalrun_67e0c7d31560819090d60c0780591042",
  "has_more": true
}

```

