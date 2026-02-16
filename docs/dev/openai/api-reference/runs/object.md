# The run object

Represents an execution run on a [thread](/docs/api-reference/threads).

## Properties

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

## Property Details

### `id` (required)

The identifier, which can be referenced in API endpoints.

**Type**: string

### `object` (required)

The object type, which is always `thread.run`.

**Type**: string

**Allowed values**: `thread.run`

### `created_at` (required)

The Unix timestamp (in seconds) for when the run was created.

**Type**: integer

### `thread_id` (required)

The ID of the [thread](/docs/api-reference/threads) that was executed on as a part of this run.

**Type**: string

### `assistant_id` (required)

The ID of the [assistant](/docs/api-reference/assistants) used for execution of this run.

**Type**: string

### `status` (required)

The status of the run, which can be either `queued`, `in_progress`, `requires_action`, `cancelling`, `cancelled`, `failed`, `completed`, `incomplete`, or `expired`.

**Type**: string

**Allowed values**: `queued`, `in_progress`, `requires_action`, `cancelling`, `cancelled`, `failed`, `completed`, `incomplete`, `expired`

### `required_action` (required)

Details on the action required to continue the run. Will be `null` if no action is required.

**Type**: object (2 properties)

**Nullable**: Yes

**Nested Properties**:

* `type`, `submit_tool_outputs`

### `last_error` (required)

The last error associated with this run. Will be `null` if there are no errors.

**Type**: object (2 properties)

**Nullable**: Yes

**Nested Properties**:

* `code`, `message`

### `expires_at` (required)

The Unix timestamp (in seconds) for when the run will expire.

**Type**: integer

**Nullable**: Yes

### `started_at` (required)

The Unix timestamp (in seconds) for when the run was started.

**Type**: integer

**Nullable**: Yes

### `cancelled_at` (required)

The Unix timestamp (in seconds) for when the run was cancelled.

**Type**: integer

**Nullable**: Yes

### `failed_at` (required)

The Unix timestamp (in seconds) for when the run failed.

**Type**: integer

**Nullable**: Yes

### `completed_at` (required)

The Unix timestamp (in seconds) for when the run was completed.

**Type**: integer

**Nullable**: Yes

### `incomplete_details` (required)

Details on why the run is incomplete. Will be `null` if the run is not incomplete.

**Type**: object (1 property)

**Nullable**: Yes

**Nested Properties**:

* `reason`

### `model` (required)

The model that the [assistant](/docs/api-reference/assistants) used for this run.

**Type**: string

### `instructions` (required)

The instructions that the [assistant](/docs/api-reference/assistants) used for this run.

**Type**: string

### `tools` (required)

The list of tools that the [assistant](/docs/api-reference/assistants) used for this run.

**Type**: array of oneOf: object (1 property) | object (2 properties) | object (2 properties)

### `metadata` (required)

Set of 16 key-value pairs that can be attached to an object. This can be
useful for storing additional information about the object in a structured
format, and querying for objects via API or the dashboard. 

Keys are strings with a maximum length of 64 characters. Values are strings
with a maximum length of 512 characters.


**Type**: map

**Nullable**: Yes

### `usage` (required)

Usage statistics related to the run. This value will be `null` if the run is not in a terminal state (i.e. `in_progress`, `queued`, etc.).

**Type**: object (3 properties)

**Nullable**: Yes

**Nested Properties**:

* `completion_tokens`, `prompt_tokens`, `total_tokens`

### `temperature`

The sampling temperature used for this run. If not set, defaults to 1.

**Type**: number

**Nullable**: Yes

### `top_p`

The nucleus sampling value used for this run. If not set, defaults to 1.

**Type**: number

**Nullable**: Yes

### `max_prompt_tokens` (required)

The maximum number of prompt tokens specified to have been used over the course of the run.


**Type**: integer

**Nullable**: Yes

### `max_completion_tokens` (required)

The maximum number of completion tokens specified to have been used over the course of the run.


**Type**: integer

**Nullable**: Yes

### `truncation_strategy` (required)

Controls for how a thread will be truncated prior to the run. Use this to control the intial context window of the run.

**Type**: object (2 properties)

**Nullable**: Yes

**Nested Properties**:

* `type`, `last_messages`

### `tool_choice` (required)

Controls which (if any) tool is called by the model.
`none` means the model will not call any tools and instead generates a message.
`auto` is the default value and means the model can pick between generating a message or calling one or more tools.
`required` means the model must call one or more tools before responding to the user.
Specifying a particular tool like `{"type": "file_search"}` or `{"type": "function", "function": {"name": "my_function"}}` forces the model to call that tool.


**Type**: oneOf: string | object (2 properties)

**Nullable**: Yes

### `parallel_tool_calls` (required)

Whether to enable [parallel function calling](/docs/guides/function-calling#configuring-parallel-function-calling) during tool use.

**Type**: boolean

### `response_format` (required)

Specifies the format that the model must output. Compatible with [GPT-4o](/docs/models#gpt-4o), [GPT-4 Turbo](/docs/models#gpt-4-turbo-and-gpt-4), and all GPT-3.5 Turbo models since `gpt-3.5-turbo-1106`.

Setting to `{ "type": "json_schema", "json_schema": {...} }` enables Structured Outputs which ensures the model will match your supplied JSON schema. Learn more in the [Structured Outputs guide](/docs/guides/structured-outputs).

Setting to `{ "type": "json_object" }` enables JSON mode, which ensures the message the model generates is valid JSON.

**Important:** when using JSON mode, you **must** also instruct the model to produce JSON yourself via a system or user message. Without this, the model may generate an unending stream of whitespace until the generation reaches the token limit, resulting in a long-running and seemingly "stuck" request. Also note that the message content may be partially cut off if `finish_reason="length"`, which indicates the generation exceeded `max_tokens` or the conversation exceeded the max context length.


**Type**: oneOf: string | object (1 property) | object (1 property) | object (2 properties)

**Nullable**: Yes

## Example

```json
{
  "id": "run_abc123",
  "object": "thread.run",
  "created_at": 1698107661,
  "assistant_id": "asst_abc123",
  "thread_id": "thread_abc123",
  "status": "completed",
  "started_at": 1699073476,
  "expires_at": null,
  "cancelled_at": null,
  "failed_at": null,
  "completed_at": 1699073498,
  "last_error": null,
  "model": "gpt-4o",
  "instructions": null,
  "tools": [{"type": "file_search"}, {"type": "code_interpreter"}],
  "metadata": {},
  "incomplete_details": null,
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

```

