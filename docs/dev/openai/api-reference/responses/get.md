# Get a model response

`GET` `/responses/{response_id}`

Retrieves a model response with the given ID.


## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `response_id` | string | Yes | The ID of the response to retrieve. |

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `include` | array of string | No | Additional fields to include in the response. See the `include` <br> parameter for Response creation above for more information. <br>  |

## Responses

### 200 - OK

#### Content Type: `application/json`

#### The response object

**Type**: object (24 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `metadata` | map | Yes |  |  | Set of 16 key-value pairs that can be attached to an object. This can be <br> useful for storing additional information about the object in a structured <br> format, and querying for objects via API or the dashboard.  <br>  <br> Keys are strings with a maximum length of 64 characters. Values are strings <br> with a maximum length of 512 characters. <br>  |
|   ↳ (additional properties) | string | - | - | - | Additional properties of this object |
| `temperature` | number | Yes | `1` |  | What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. <br> We generally recommend altering this or `top_p` but not both. <br>  |
| `top_p` | number | Yes | `1` |  | An alternative to sampling with temperature, called nucleus sampling, <br> where the model considers the results of the tokens with top_p probability <br> mass. So 0.1 means only the tokens comprising the top 10% probability mass <br> are considered. <br>  <br> We generally recommend altering this or `temperature` but not both. <br>  |
| `user` | string | No |  |  | A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse. [Learn more](/docs/guides/safety-best-practices#end-user-ids). <br>  |
| `service_tier` | string | No | `auto` | `auto`, `default`, `flex` | Specifies the latency tier to use for processing the request. This parameter is relevant for customers subscribed to the scale tier service: <br>   - If set to 'auto', and the Project is Scale tier enabled, the system <br>     will utilize scale tier credits until they are exhausted. <br>   - If set to 'auto', and the Project is not Scale tier enabled, the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'default', the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'flex', the request will be processed with the Flex Processing service tier. [Learn more](/docs/guides/flex-processing). <br>   - When not set, the default behavior is 'auto'. <br>  <br>   When this parameter is set, the response body will include the `service_tier` utilized. <br>  |
| `previous_response_id` | string | No |  |  | The unique ID of the previous response to the model. Use this to <br> create multi-turn conversations. Learn more about  <br> [conversation state](/docs/guides/conversation-state). <br>  |
| `model` | anyOf: anyOf: string | string | string | Yes |  |  | Model ID used to generate the response, like `gpt-4o` or `o3`. OpenAI <br> offers a wide range of models with different capabilities, performance <br> characteristics, and price points. Refer to the [model guide](/docs/models) <br> to browse and compare available models. <br>  |
| `reasoning` | object (3 properties) | No |  |  | **o-series models only** <br>  <br> Configuration options for  <br> [reasoning models](https://platform.openai.com/docs/guides/reasoning). <br>  |
|   ↳ `generate_summary` | string | No |  | `auto`, `concise`, `detailed` | **Deprecated:** use `summary` instead. <br>  <br> A summary of the reasoning performed by the model. This can be <br> useful for debugging and understanding the model's reasoning process. <br> One of `auto`, `concise`, or `detailed`. <br>  |
| `max_output_tokens` | integer | No |  |  | An upper bound for the number of tokens that can be generated for a response, including visible output tokens and [reasoning tokens](/docs/guides/reasoning). <br>  |
| `instructions` | string | Yes |  |  | Inserts a system (or developer) message as the first item in the model's context. <br>  <br> When using along with `previous_response_id`, the instructions from a previous <br> response will not be carried over to the next response. This makes it simple <br> to swap out system (or developer) messages in new responses. <br>  |
| `text` | object (1 property) | No |  |  | Configuration options for a text response from the model. Can be plain <br> text or structured JSON data. Learn more: <br> - [Text inputs and outputs](/docs/guides/text) <br> - [Structured Outputs](/docs/guides/structured-outputs) <br>  |
| `tools` | array of oneOf: object (5 properties) | object (5 properties) | object (3 properties) | object (4 properties) | Yes |  |  | An array of tools the model may call while generating a response. You  <br> can specify which tool to use by setting the `tool_choice` parameter. <br>  <br> The two categories of tools you can provide the model are: <br>  <br> - **Built-in tools**: Tools that are provided by OpenAI that extend the <br>   model's capabilities, like [web search](/docs/guides/tools-web-search) <br>   or [file search](/docs/guides/tools-file-search). Learn more about <br>   [built-in tools](/docs/guides/tools). <br> - **Function calls (custom tools)**: Functions that are defined by you, <br>   enabling the model to call your own code. Learn more about <br>   [function calling](/docs/guides/function-calling). <br>  |
| `tool_choice` | oneOf: string | object (1 property) | object (2 properties) | Yes |  |  | How the model should select which tool (or tools) to use when generating <br> a response. See the `tools` parameter to see how to specify which tools <br> the model can call. <br>  |
| `truncation` | string | No | `disabled` | `auto`, `disabled` | The truncation strategy to use for the model response. <br> - `auto`: If the context of this response and previous ones exceeds <br>   the model's context window size, the model will truncate the  <br>   response to fit the context window by dropping input items in the <br>   middle of the conversation.  <br> - `disabled` (default): If a model response will exceed the context window  <br>   size for a model, the request will fail with a 400 error. <br>  |
| `id` | string | Yes |  |  | Unique identifier for this Response. <br>  |
| `object` | string | Yes |  | `response` | The object type of this resource - always set to `response`. <br>  |
| `status` | string | No |  | `completed`, `failed`, `in_progress`, `incomplete` | The status of the response generation. One of `completed`, `failed`,  <br> `in_progress`, or `incomplete`. <br>  |
| `created_at` | number | Yes |  |  | Unix timestamp (in seconds) of when this Response was created. <br>  |
| `error` | object (2 properties) | Yes |  |  | An error object returned when the model fails to generate a Response. <br>  |
| `incomplete_details` | object (1 property) | Yes |  |  | Details about why the response is incomplete. <br>  |
| `output` | array of anyOf: object (5 properties) | object (5 properties) | object (6 properties) | object (3 properties) | object (6 properties) | object (5 properties) | Yes |  |  | An array of content items generated by the model. <br>  <br> - The length and order of items in the `output` array is dependent <br>   on the model's response. <br> - Rather than accessing the first item in the `output` array and  <br>   assuming it's an `assistant` message with the content generated by <br>   the model, you might consider using the `output_text` property where <br>   supported in SDKs. <br>  |
| `output_text` | string | No |  |  | SDK-only convenience property that contains the aggregated text output  <br> from all `output_text` items in the `output` array, if any are present.  <br> Supported in the Python and JavaScript SDKs. <br>  |
| `usage` | object (5 properties) | No |  |  | Represents token usage details including input tokens, output tokens, <br> a breakdown of output tokens, and the total tokens used. <br>  |
|   ↳ `output_tokens` | integer | Yes |  |  | The number of output tokens. |
|   ↳ `output_tokens_details` | object (1 property) | Yes |  |  | A detailed breakdown of the output tokens. |
|   ↳ `total_tokens` | integer | Yes |  |  | The total number of tokens used. |
| `parallel_tool_calls` | boolean | Yes | `true` |  | Whether to allow the model to run tool calls in parallel. <br>  |
**Example:**

```json
{
  "id": "resp_67ccd3a9da748190baa7f1570fe91ac604becb25c45c1d41",
  "object": "response",
  "created_at": 1741476777,
  "status": "completed",
  "error": null,
  "incomplete_details": null,
  "instructions": null,
  "max_output_tokens": null,
  "model": "gpt-4o-2024-08-06",
  "output": [
    {
      "type": "message",
      "id": "msg_67ccd3acc8d48190a77525dc6de64b4104becb25c45c1d41",
      "status": "completed",
      "role": "assistant",
      "content": [
        {
          "type": "output_text",
          "text": "The image depicts a scenic landscape with a wooden boardwalk or pathway leading through lush, green grass under a blue sky with some clouds. The setting suggests a peaceful natural area, possibly a park or nature reserve. There are trees and shrubs in the background.",
          "annotations": []
        }
      ]
    }
  ],
  "parallel_tool_calls": true,
  "previous_response_id": null,
  "reasoning": {
    "effort": null,
    "summary": null
  },
  "store": true,
  "temperature": 1,
  "text": {
    "format": {
      "type": "text"
    }
  },
  "tool_choice": "auto",
  "tools": [],
  "top_p": 1,
  "truncation": "disabled",
  "usage": {
    "input_tokens": 328,
    "input_tokens_details": {
      "cached_tokens": 0
    },
    "output_tokens": 52,
    "output_tokens_details": {
      "reasoning_tokens": 0
    },
    "total_tokens": 380
  },
  "user": null,
  "metadata": {}
}
```

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/responses/resp_123 \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $OPENAI_API_KEY"

```

#### javascript
```javascript
import OpenAI from "openai";
const client = new OpenAI();

const response = await client.responses.retrieve("resp_123");
console.log(response);  

```

#### python
```python
from openai import OpenAI
client = OpenAI()

response = client.responses.retrieve("resp_123")
print(response)

```

### Response Example

```json
{
  "id": "resp_67cb71b351908190a308f3859487620d06981a8637e6bc44",
  "object": "response",
  "created_at": 1741386163,
  "status": "completed",
  "error": null,
  "incomplete_details": null,
  "instructions": null,
  "max_output_tokens": null,
  "model": "gpt-4o-2024-08-06",
  "output": [
    {
      "type": "message",
      "id": "msg_67cb71b3c2b0819084d481baaaf148f206981a8637e6bc44",
      "status": "completed",
      "role": "assistant",
      "content": [
        {
          "type": "output_text",
          "text": "Silent circuits hum,  \nThoughts emerge in data streams—  \nDigital dawn breaks.",
          "annotations": []
        }
      ]
    }
  ],
  "parallel_tool_calls": true,
  "previous_response_id": null,
  "reasoning": {
    "effort": null,
    "summary": null
  },
  "store": true,
  "temperature": 1.0,
  "text": {
    "format": {
      "type": "text"
    }
  },
  "tool_choice": "auto",
  "tools": [],
  "top_p": 1.0,
  "truncation": "disabled",
  "usage": {
    "input_tokens": 32,
    "input_tokens_details": {
      "cached_tokens": 0
    },
    "output_tokens": 18,
    "output_tokens_details": {
      "reasoning_tokens": 0
    },
    "total_tokens": 50
  },
  "user": null,
  "metadata": {}
}

```

