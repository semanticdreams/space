# The eval run object

A schema representing an evaluation run.


## Properties

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

## Property Details

### `object` (required)

The type of the object. Always "eval.run".

**Type**: string

**Allowed values**: `eval.run`

### `id` (required)

Unique identifier for the evaluation run.

**Type**: string

### `eval_id` (required)

The identifier of the associated evaluation.

**Type**: string

### `status` (required)

The status of the evaluation run.

**Type**: string

### `model` (required)

The model that is evaluated, if applicable.

**Type**: string

### `name` (required)

The name of the evaluation run.

**Type**: string

### `created_at` (required)

Unix timestamp (in seconds) when the evaluation run was created.

**Type**: integer

### `report_url` (required)

The URL to the rendered evaluation run report on the UI dashboard.

**Type**: string

### `result_counts` (required)

Counters summarizing the outcomes of the evaluation run.

**Type**: object (4 properties)

**Nested Properties**:

* `total`, `errored`, `failed`, `passed`

### `per_model_usage` (required)

Usage statistics for each model during the evaluation run.

**Type**: array of object (6 properties)

### `per_testing_criteria_results` (required)

Results per testing criteria applied during the evaluation run.

**Type**: array of object (3 properties)

### `data_source` (required)

Information about the run's data source.

**Type**: object

### `metadata` (required)

Set of 16 key-value pairs that can be attached to an object. This can be
useful for storing additional information about the object in a structured
format, and querying for objects via API or the dashboard. 

Keys are strings with a maximum length of 64 characters. Values are strings
with a maximum length of 512 characters.


**Type**: map

**Nullable**: Yes

### `error` (required)

An object representing an error response from the Eval API.


**Type**: object (2 properties)

**Nested Properties**:

* `code`, `message`

## Example

```json
{
  "object": "eval.run",
  "id": "evalrun_67e57965b480819094274e3a32235e4c",
  "eval_id": "eval_67e579652b548190aaa83ada4b125f47",
  "report_url": "https://platform.openai.com/evaluations/eval_67e579652b548190aaa83ada4b125f47?run_id=evalrun_67e57965b480819094274e3a32235e4c",
  "status": "queued",
  "model": "gpt-4o-mini",
  "name": "gpt-4o-mini",
  "created_at": 1743092069,
  "result_counts": {
    "total": 0,
    "errored": 0,
    "failed": 0,
    "passed": 0
  },
  "per_model_usage": null,
  "per_testing_criteria_results": null,
  "data_source": {
    "type": "completions",
    "source": {
      "type": "file_content",
      "content": [
        {
          "item": {
            "input": "Tech Company Launches Advanced Artificial Intelligence Platform",
            "ground_truth": "Technology"
          }
        },
        {
          "item": {
            "input": "Central Bank Increases Interest Rates Amid Inflation Concerns",
            "ground_truth": "Markets"
          }
        },
        {
          "item": {
            "input": "International Summit Addresses Climate Change Strategies",
            "ground_truth": "World"
          }
        },
        {
          "item": {
            "input": "Major Retailer Reports Record-Breaking Holiday Sales",
            "ground_truth": "Business"
          }
        },
        {
          "item": {
            "input": "National Team Qualifies for World Championship Finals",
            "ground_truth": "Sports"
          }
        },
        {
          "item": {
            "input": "Stock Markets Rally After Positive Economic Data Released",
            "ground_truth": "Markets"
          }
        },
        {
          "item": {
            "input": "Global Manufacturer Announces Merger with Competitor",
            "ground_truth": "Business"
          }
        },
        {
          "item": {
            "input": "Breakthrough in Renewable Energy Technology Unveiled",
            "ground_truth": "Technology"
          }
        },
        {
          "item": {
            "input": "World Leaders Sign Historic Climate Agreement",
            "ground_truth": "World"
          }
        },
        {
          "item": {
            "input": "Professional Athlete Sets New Record in Championship Event",
            "ground_truth": "Sports"
          }
        },
        {
          "item": {
            "input": "Financial Institutions Adapt to New Regulatory Requirements",
            "ground_truth": "Business"
          }
        },
        {
          "item": {
            "input": "Tech Conference Showcases Advances in Artificial Intelligence",
            "ground_truth": "Technology"
          }
        },
        {
          "item": {
            "input": "Global Markets Respond to Oil Price Fluctuations",
            "ground_truth": "Markets"
          }
        },
        {
          "item": {
            "input": "International Cooperation Strengthened Through New Treaty",
            "ground_truth": "World"
          }
        },
        {
          "item": {
            "input": "Sports League Announces Revised Schedule for Upcoming Season",
            "ground_truth": "Sports"
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
            "text": "Categorize a given news headline into one of the following topics: Technology, Markets, World, Business, or Sports.\n\n# Steps\n\n1. Analyze the content of the news headline to understand its primary focus.\n2. Extract the subject matter, identifying any key indicators or keywords.\n3. Use the identified indicators to determine the most suitable category out of the five options: Technology, Markets, World, Business, or Sports.\n4. Ensure only one category is selected per headline.\n\n# Output Format\n\nRespond with the chosen category as a single word. For instance: \"Technology\", \"Markets\", \"World\", \"Business\", or \"Sports\".\n\n# Examples\n\n**Input**: \"Apple Unveils New iPhone Model, Featuring Advanced AI Features\"  \n**Output**: \"Technology\"\n\n**Input**: \"Global Stocks Mixed as Investors Await Central Bank Decisions\"  \n**Output**: \"Markets\"\n\n**Input**: \"War in Ukraine: Latest Updates on Negotiation Status\"  \n**Output**: \"World\"\n\n**Input**: \"Microsoft in Talks to Acquire Gaming Company for $2 Billion\"  \n**Output**: \"Business\"\n\n**Input**: \"Manchester United Secures Win in Premier League Football Match\"  \n**Output**: \"Sports\" \n\n# Notes\n\n- If the headline appears to fit into more than one category, choose the most dominant theme.\n- Keywords or phrases such as \"stocks\", \"company acquisition\", \"match\", or technological brands can be good indicators for classification.\n"
          }
        },
        {
          "type": "message",
          "role": "user",
          "content": {
            "type": "input_text",
            "text": "{{item.input}}"
          }
        }
      ]
    },
    "model": "gpt-4o-mini",
    "sampling_params": {
      "seed": 42,
      "temperature": 1.0,
      "top_p": 1.0,
      "max_completions_tokens": 2048
    }
  },
  "error": null,
  "metadata": {}
}

```

