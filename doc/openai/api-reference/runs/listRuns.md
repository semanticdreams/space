# List runs

`GET` `/threads/{thread_id}/runs`

Returns a list of runs belonging to a thread.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `thread_id` | string | Yes | The ID of the thread the run belongs to. |

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `limit` | integer | No | A limit on the number of objects to be returned. Limit can range between 1 and 100, and the default is 20. <br>  |
| `order` | string | No | Sort order by the `created_at` timestamp of the objects. `asc` for ascending order and `desc` for descending order. <br>  |
| `after` | string | No | A cursor for use in pagination. `after` is an object ID that defines your place in the list. For instance, if you make a list request and receive 100 objects, ending with obj_foo, your subsequent call can include after=obj_foo in order to fetch the next page of the list. <br>  |
| `before` | string | No | A cursor for use in pagination. `before` is an object ID that defines your place in the list. For instance, if you make a list request and receive 100 objects, starting with obj_foo, your subsequent call can include before=obj_foo in order to fetch the previous page of the list. <br>  |

## Responses

### 200 - OK

#### Content Type: `application/json`

**Type**: object (5 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  |  |  |
| `data` | array of object (27 properties) | Yes |  |  |  |
| `first_id` | string | Yes |  |  |  |
| `last_id` | string | Yes |  |  |  |
| `has_more` | boolean | Yes |  |  |  |


### Items in `data` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints. |
| `object` | string | Yes |  | `thread.run` | The object type, which is always `thread.run`. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the run was created. |
| `thread_id` | string | Yes |  |  | The ID of the [thread](/docs/api-reference/threads) that was executed on as a part of this run. |
| `assistant_id` | string | Yes |  |  | The ID of the [assistant](/docs/api-reference/assistants) used for execution of this run. |
| `status` | string | Yes |  | `queued`, `in_progress`, `requires_action`, `cancelling`, `cancelled`, `failed`, `completed`, `incomplete`, `expired` | The status of the run, which can be either `queued`, `in_progress`, `requires_action`, `cancelling`, `cancelled`, `failed`, `completed`, `incomplete`, or `expired`. |
| `required_action` | object (2 properties) | Yes |  |  | Details on the action required to continue the run. Will be `null` if no action is required. |

### Items in `tool_calls` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The ID of the tool call. This ID must be referenced when you submit the tool outputs in using the [Submit tool outputs to run](/docs/api-reference/runs/submitToolOutputs) endpoint. |
| `type` | string | Yes |  | `function` | The type of tool call the output is required for. For now, this is always `function`. |
| `function` | object (2 properties) | Yes |  |  | The function definition. |
| `last_error` | object (2 properties) | Yes |  |  | The last error associated with this run. Will be `null` if there are no errors. |
| `expires_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the run will expire. |
| `started_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the run was started. |
| `cancelled_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the run was cancelled. |
| `failed_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the run failed. |
| `completed_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the run was completed. |
| `incomplete_details` | object (1 property) | Yes |  |  | Details on why the run is incomplete. Will be `null` if the run is not incomplete. |
| `model` | string | Yes |  |  | The model that the [assistant](/docs/api-reference/assistants) used for this run. |
| `instructions` | string | Yes |  |  | The instructions that the [assistant](/docs/api-reference/assistants) used for this run. |
| `tools` | array of oneOf: object (1 property) | object (2 properties) | object (2 properties) | Yes | `[]` |  | The list of tools that the [assistant](/docs/api-reference/assistants) used for this run. |
| `metadata` | map | Yes |  |  | Set of 16 key-value pairs that can be attached to an object. This can be <br> useful for storing additional information about the object in a structured <br> format, and querying for objects via API or the dashboard.  <br>  <br> Keys are strings with a maximum length of 64 characters. Values are strings <br> with a maximum length of 512 characters. <br>  |
|   ↳ (additional properties) | string | - | - | - | Additional properties of this object |
| `usage` | object (3 properties) | Yes |  |  | Usage statistics related to the run. This value will be `null` if the run is not in a terminal state (i.e. `in_progress`, `queued`, etc.). |
|   ↳ `total_tokens` | integer | Yes |  |  | Total number of tokens used (prompt + completion). |
| `temperature` | number | No |  |  | The sampling temperature used for this run. If not set, defaults to 1. |
| `top_p` | number | No |  |  | The nucleus sampling value used for this run. If not set, defaults to 1. |
| `max_prompt_tokens` | integer | Yes |  |  | The maximum number of prompt tokens specified to have been used over the course of the run. <br>  |
| `max_completion_tokens` | integer | Yes |  |  | The maximum number of completion tokens specified to have been used over the course of the run. <br>  |
| `truncation_strategy` | object (2 properties) | Yes |  |  | Controls for how a thread will be truncated prior to the run. Use this to control the intial context window of the run. |
| `tool_choice` | oneOf: string | object (2 properties) | Yes |  |  | Controls which (if any) tool is called by the model. <br> `none` means the model will not call any tools and instead generates a message. <br> `auto` is the default value and means the model can pick between generating a message or calling one or more tools. <br> `required` means the model must call one or more tools before responding to the user. <br> Specifying a particular tool like `{"type": "file_search"}` or `{"type": "function", "function": {"name": "my_function"}}` forces the model to call that tool. <br>  |
| `parallel_tool_calls` | boolean | Yes | `true` |  | Whether to enable [parallel function calling](/docs/guides/function-calling#configuring-parallel-function-calling) during tool use. |
| `response_format` | oneOf: string | object (1 property) | object (1 property) | object (2 properties) | Yes |  |  | Specifies the format that the model must output. Compatible with [GPT-4o](/docs/models#gpt-4o), [GPT-4 Turbo](/docs/models#gpt-4-turbo-and-gpt-4), and all GPT-3.5 Turbo models since `gpt-3.5-turbo-1106`. <br>  <br> Setting to `{ "type": "json_schema", "json_schema": {...} }` enables Structured Outputs which ensures the model will match your supplied JSON schema. Learn more in the [Structured Outputs guide](/docs/guides/structured-outputs). <br>  <br> Setting to `{ "type": "json_object" }` enables JSON mode, which ensures the message the model generates is valid JSON. <br>  <br> **Important:** when using JSON mode, you **must** also instruct the model to produce JSON yourself via a system or user message. Without this, the model may generate an unending stream of whitespace until the generation reaches the token limit, resulting in a long-running and seemingly "stuck" request. Also note that the message content may be partially cut off if `finish_reason="length"`, which indicates the generation exceeded `max_tokens` or the conversation exceeded the max context length. <br>  |
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/threads/thread_abc123/runs \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -H "OpenAI-Beta: assistants=v2"

```

#### python
```python
from openai import OpenAI
client = OpenAI()

runs = client.beta.threads.runs.list(
  "thread_abc123"
)

print(runs)

```

#### node.js
```javascript
import OpenAI from "openai";

const openai = new OpenAI();

async function main() {
  const runs = await openai.beta.threads.runs.list(
    "thread_abc123"
  );

  console.log(runs);
}

main();

```

### Response Example

```json
{
  "object": "list",
  "data": [
    {
      "id": "run_abc123",
      "object": "thread.run",
      "created_at": 1699075072,
      "assistant_id": "asst_abc123",
      "thread_id": "thread_abc123",
      "status": "completed",
      "started_at": 1699075072,
      "expires_at": null,
      "cancelled_at": null,
      "failed_at": null,
      "completed_at": 1699075073,
      "last_error": null,
      "model": "gpt-4o",
      "instructions": null,
      "incomplete_details": null,
      "tools": [
        {
          "type": "code_interpreter"
        }
      ],
      "tool_resources": {
        "code_interpreter": {
          "file_ids": [
            "file-abc123",
            "file-abc456"
          ]
        }
      },
      "metadata": {},
      "usage": {
        "prompt_tokens": 123,
        "completion_tokens": 456,
        "total_tokens": 579
      },
      "temperature": 1.0,
      "top_p": 1.0,
      "max_prompt_tokens": 1000,
      "max_completion_tokens": 1000,
      "truncation_strategy": {
        "type": "auto",
        "last_messages": null
      },
      "response_format": "auto",
      "tool_choice": "auto",
      "parallel_tool_calls": true
    },
    {
      "id": "run_abc456",
      "object": "thread.run",
      "created_at": 1699063290,
      "assistant_id": "asst_abc123",
      "thread_id": "thread_abc123",
      "status": "completed",
      "started_at": 1699063290,
      "expires_at": null,
      "cancelled_at": null,
      "failed_at": null,
      "completed_at": 1699063291,
      "last_error": null,
      "model": "gpt-4o",
      "instructions": null,
      "incomplete_details": null,
      "tools": [
        {
          "type": "code_interpreter"
        }
      ],
      "tool_resources": {
        "code_interpreter": {
          "file_ids": [
            "file-abc123",
            "file-abc456"
          ]
        }
      },
      "metadata": {},
      "usage": {
        "prompt_tokens": 123,
        "completion_tokens": 456,
        "total_tokens": 579
      },
      "temperature": 1.0,
      "top_p": 1.0,
      "max_prompt_tokens": 1000,
      "max_completion_tokens": 1000,
      "truncation_strategy": {
        "type": "auto",
        "last_messages": null
      },
      "response_format": "auto",
      "tool_choice": "auto",
      "parallel_tool_calls": true
    }
  ],
  "first_id": "run_abc123",
  "last_id": "run_abc456",
  "has_more": false
}

```

