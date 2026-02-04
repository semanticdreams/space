# Get eval run output items

`GET` `/evals/{eval_id}/runs/{run_id}/output_items`

Get a list of output items for an evaluation run.


## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `eval_id` | string | Yes | The ID of the evaluation to retrieve runs for. |
| `run_id` | string | Yes | The ID of the run to retrieve output items for. |

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `after` | string | No | Identifier for the last output item from the previous pagination request. |
| `limit` | integer | No | Number of output items to retrieve. |
| `status` | string | No | Filter output items by status. Use `failed` to filter by failed output <br> items or `pass` to filter by passed output items. <br>  |
| `order` | string | No | Sort order for output items by timestamp. Use `asc` for ascending order or `desc` for descending order. Defaults to `asc`. |

## Responses

### 200 - A list of output items for the evaluation run

#### Content Type: `application/json`

#### EvalRunOutputItemList

**Type**: object (5 properties)

An object representing a list of output items for an evaluation run.


#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes | `list` | `list` | The type of this object. It is always set to "list". <br>  |
| `data` | array of object (10 properties) | Yes |  |  | An array of eval run output item objects. <br>  |
| `first_id` | string | Yes |  |  | The identifier of the first eval run output item in the data array. |
| `last_id` | string | Yes |  |  | The identifier of the last eval run output item in the data array. |
| `has_more` | boolean | Yes |  |  | Indicates whether there are more eval run output items available. |


### Items in `data` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes | `eval.run.output_item` | `eval.run.output_item` | The type of the object. Always "eval.run.output_item". |
| `id` | string | Yes |  |  | Unique identifier for the evaluation run output item. |
| `run_id` | string | Yes |  |  | The identifier of the evaluation run associated with this output item. |
| `eval_id` | string | Yes |  |  | The identifier of the evaluation group. |
| `created_at` | integer | Yes |  |  | Unix timestamp (in seconds) when the evaluation run was created. |
| `status` | string | Yes |  |  | The status of the evaluation run. |
| `datasource_item_id` | integer | Yes |  |  | The identifier for the data source item. |
| `datasource_item` | object (map of object) | Yes |  |  | Details of the input data source item. |
|   ↳ (additional properties) | object | - | - | - | Additional properties of this object |
| `results` | array of object (map of object) | Yes |  |  | A list of results from the evaluation run. |
| `sample` | object (10 properties) | Yes |  |  | A sample containing the input and output of the evaluation run. |
|   ↳ `finish_reason` | string | Yes |  |  | The reason why the sample generation was finished. |
|   ↳ `model` | string | Yes |  |  | The model used for generating the sample. |
|   ↳ `usage` | object (4 properties) | Yes |  |  | Token usage details for the sample. |
|     ↳ `prompt_tokens` | integer | Yes |  |  | The number of prompt tokens used. |
|     ↳ `cached_tokens` | integer | Yes |  |  | The number of tokens retrieved from cache. |
|   ↳ `error` | object (2 properties) | Yes |  |  | An object representing an error response from the Eval API. <br>  |
|   ↳ `temperature` | number | Yes |  |  | The sampling temperature used. |
|   ↳ `max_completion_tokens` | integer | Yes |  |  | The maximum number of tokens allowed for completion. |
|   ↳ `top_p` | number | Yes |  |  | The top_p value used for sampling. |
|   ↳ `seed` | integer | Yes |  |  | The seed used for generating the sample. |


### Items in `input` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `role` | string | Yes |  |  | The role of the message sender (e.g., system, user, developer). |
| `content` | string | Yes |  |  | The content of the message. |


### Items in `output` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `role` | string | No |  |  | The role of the message (e.g. "system", "assistant", "user"). |
| `content` | string | No |  |  | The content of the message. |


### Items in `results` array

Each item is of type `object (map of object)` - A result object.

**Example:**

```json
{
  "object": "list",
  "data": [
    {
      "object": "eval.run.output_item",
      "id": "outputitem_67abd55eb6548190bb580745d5644a33",
      "run_id": "evalrun_67abd54d60ec8190832b46859da808f7",
      "eval_id": "eval_67abd54d9b0081909a86353f6fb9317a",
      "created_at": 1739314509,
      "status": "pass",
      "datasource_item_id": 137,
      "datasource_item": {
          "teacher": "To grade essays, I only check for style, content, and grammar.",
          "student": "I am a student who is trying to write the best essay."
      },
      "results": [
        {
          "name": "String Check Grader",
          "type": "string-check-grader",
          "score": 1.0,
          "passed": true,
        }
      ],
      "sample": {
        "input": [
          {
            "role": "system",
            "content": "You are an evaluator bot..."
          },
          {
            "role": "user",
            "content": "You are assessing..."
          }
        ],
        "output": [
          {
            "role": "assistant",
            "content": "The rubric is not clear nor concise."
          }
        ],
        "finish_reason": "stop",
        "model": "gpt-4o-2024-08-06",
        "usage": {
          "total_tokens": 521,
          "completion_tokens": 2,
          "prompt_tokens": 519,
          "cached_tokens": 0
        },
        "error": null,
        "temperature": 1.0,
        "max_completion_tokens": 2048,
        "top_p": 1.0,
        "seed": 42
      }
    },
  ],
  "first_id": "outputitem_67abd55eb6548190bb580745d5644a33",
  "last_id": "outputitem_67abd55eb6548190bb580745d5644a33",
  "has_more": false
}

```

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/evals/egroup_67abd54d9b0081909a86353f6fb9317a/runs/erun_67abd54d60ec8190832b46859da808f7/output_items \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json"

```

### Response Example

```json
{
  "object": "list",
  "data": [
    {
      "object": "eval.run.output_item",
      "id": "outputitem_67e5796c28e081909917bf79f6e6214d",
      "created_at": 1743092076,
      "run_id": "evalrun_67abd54d60ec8190832b46859da808f7",
      "eval_id": "eval_67abd54d9b0081909a86353f6fb9317a",
      "status": "pass",
      "datasource_item_id": 5,
      "datasource_item": {
        "input": "Stock Markets Rally After Positive Economic Data Released",
        "ground_truth": "Markets"
      },
      "results": [
        {
          "name": "String check-a2486074-d803-4445-b431-ad2262e85d47",
          "sample": null,
          "passed": true,
          "score": 1.0
        }
      ],
      "sample": {
        "input": [
          {
            "role": "developer",
            "content": "Categorize a given news headline into one of the following topics: Technology, Markets, World, Business, or Sports.\n\n# Steps\n\n1. Analyze the content of the news headline to understand its primary focus.\n2. Extract the subject matter, identifying any key indicators or keywords.\n3. Use the identified indicators to determine the most suitable category out of the five options: Technology, Markets, World, Business, or Sports.\n4. Ensure only one category is selected per headline.\n\n# Output Format\n\nRespond with the chosen category as a single word. For instance: \"Technology\", \"Markets\", \"World\", \"Business\", or \"Sports\".\n\n# Examples\n\n**Input**: \"Apple Unveils New iPhone Model, Featuring Advanced AI Features\"  \n**Output**: \"Technology\"\n\n**Input**: \"Global Stocks Mixed as Investors Await Central Bank Decisions\"  \n**Output**: \"Markets\"\n\n**Input**: \"War in Ukraine: Latest Updates on Negotiation Status\"  \n**Output**: \"World\"\n\n**Input**: \"Microsoft in Talks to Acquire Gaming Company for $2 Billion\"  \n**Output**: \"Business\"\n\n**Input**: \"Manchester United Secures Win in Premier League Football Match\"  \n**Output**: \"Sports\" \n\n# Notes\n\n- If the headline appears to fit into more than one category, choose the most dominant theme.\n- Keywords or phrases such as \"stocks\", \"company acquisition\", \"match\", or technological brands can be good indicators for classification.\n",
            "tool_call_id": null,
            "tool_calls": null,
            "function_call": null
          },
          {
            "role": "user",
            "content": "Stock Markets Rally After Positive Economic Data Released",
            "tool_call_id": null,
            "tool_calls": null,
            "function_call": null
          }
        ],
        "output": [
          {
            "role": "assistant",
            "content": "Markets",
            "tool_call_id": null,
            "tool_calls": null,
            "function_call": null
          }
        ],
        "finish_reason": "stop",
        "model": "gpt-4o-mini-2024-07-18",
        "usage": {
          "total_tokens": 325,
          "completion_tokens": 2,
          "prompt_tokens": 323,
          "cached_tokens": 0
        },
        "error": null,
        "temperature": 1.0,
        "max_completion_tokens": 2048,
        "top_p": 1.0,
        "seed": 42
      }
    }
  ],
  "first_id": "outputitem_67e5796c28e081909917bf79f6e6214d",
  "last_id": "outputitem_67e5796c28e081909917bf79f6e6214d",
  "has_more": true
}

```

