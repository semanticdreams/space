# response.create

This event instructs the server to create a Response, which means triggering 
model inference. When in Server VAD mode, the server will create Responses 
automatically.

A Response will include at least one Item, and may have two, in which case 
the second will be a function call. These Items will be appended to the 
conversation history.

The server will respond with a `response.created` event, events for Items 
and content created, and finally a `response.done` event to indicate the 
Response is complete.

The `response.create` event includes inference configuration like 
`instructions`, and `temperature`. These fields will override the Session's 
configuration for this Response only.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | No |  |  | Optional client-generated ID used to identify this event. |
| `type` | string | Yes |  | `response.create` | The event type, must be `response.create`. |
| `response` | object (11 properties) | No |  |  | Create a new Realtime response with these parameters |
|   ↳ `voice` | anyOf: string | string | No |  |  | The voice the model uses to respond. Voice cannot be changed during the  <br> session once the model has responded with audio at least once. Current  <br> voice options are `alloy`, `ash`, `ballad`, `coral`, `echo`, `fable`, <br> `onyx`, `nova`, `sage`, `shimmer`, and `verse`. <br>  |
|   ↳ `output_audio_format` | string | No |  | `pcm16`, `g711_ulaw`, `g711_alaw` | The format of output audio. Options are `pcm16`, `g711_ulaw`, or `g711_alaw`. <br>  |
|   ↳ `tools` | array of object (4 properties) | No |  |  | Tools (functions) available to the model. |
|   ↳ `tool_choice` | string | No |  |  | How the model chooses tools. Options are `auto`, `none`, `required`, or  <br> specify a function, like `{"type": "function", "function": {"name": "my_function"}}`. <br>  |
|   ↳ `temperature` | number | No |  |  | Sampling temperature for the model, limited to [0.6, 1.2]. Defaults to 0.8. <br>  |
|   ↳ `max_response_output_tokens` | oneOf: integer | string | No |  |  | Maximum number of output tokens for a single assistant response, <br> inclusive of tool calls. Provide an integer between 1 and 4096 to <br> limit output tokens, or `inf` for the maximum available tokens for a <br> given model. Defaults to `inf`. <br>  |
|   ↳ `conversation` | oneOf: string | string | No |  |  | Controls which conversation the response is added to. Currently supports <br> `auto` and `none`, with `auto` as the default value. The `auto` value <br> means that the contents of the response will be added to the default <br> conversation. Set this to `none` to create an out-of-band response which  <br> will not add items to default conversation. <br>  |
|   ↳ `metadata` | map | No |  |  | Set of 16 key-value pairs that can be attached to an object. This can be <br> useful for storing additional information about the object in a structured <br> format, and querying for objects via API or the dashboard.  <br>  <br> Keys are strings with a maximum length of 64 characters. Values are strings <br> with a maximum length of 512 characters. <br>  |
|   ↳   ↳ (additional properties) | string | - | - | - | Additional properties of this object |
|   ↳ `input` | array of object (10 properties) | No |  |  | Input items to include in the prompt for the model. Using this field <br> creates a new context for this Response instead of using the default <br> conversation. An empty array `[]` will clear the context for this Response. <br> Note that this can include references to items from the default conversation. <br>  |


### Items in `modalities` array

Each item is of type `string`. Allowed values: `text`, `audio`



### Items in `tools` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | No |  | `function` | The type of the tool, i.e. `function`. |
| `name` | string | No |  |  | The name of the function. |
| `description` | string | No |  |  | The description of the function, including guidance on when and how  <br> to call it, and guidance about what to tell the user when calling  <br> (if anything). <br>  |
| `parameters` | object | No |  |  | Parameters of the function in JSON Schema. |


### Items in `input` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | No |  |  | For an item of type (`message` | `function_call` | `function_call_output`) <br> this field allows the client to assign the unique ID of the item. It is <br> not required because the server will generate one if not provided. <br>  <br> For an item of type `item_reference`, this field is required and is a <br> reference to any item that has previously existed in the conversation. <br>  |
| `type` | string | No |  | `message`, `function_call`, `function_call_output` | The type of the item (`message`, `function_call`, `function_call_output`, `item_reference`). <br>  |
| `object` | string | No |  | `realtime.item` | Identifier for the API object being returned - always `realtime.item`. <br>  |
| `status` | string | No |  | `completed`, `incomplete` | The status of the item (`completed`, `incomplete`). These have no effect  <br> on the conversation, but are accepted for consistency with the  <br> `conversation.item.created` event. <br>  |
| `role` | string | No |  | `user`, `assistant`, `system` | The role of the message sender (`user`, `assistant`, `system`), only  <br> applicable for `message` items. <br>  |
| `content` | array of object (5 properties) | No |  |  | The content of the message, applicable for `message` items.  <br> - Message items of role `system` support only `input_text` content <br> - Message items of role `user` support `input_text` and `input_audio`  <br>   content <br> - Message items of role `assistant` support `text` content. <br>  |
| `call_id` | string | No |  |  | The ID of the function call (for `function_call` and  <br> `function_call_output` items). If passed on a `function_call_output`  <br> item, the server will check that a `function_call` item with the same  <br> ID exists in the conversation history. <br>  |
| `name` | string | No |  |  | The name of the function being called (for `function_call` items). <br>  |
| `arguments` | string | No |  |  | The arguments of the function call (for `function_call` items). <br>  |
| `output` | string | No |  |  | The output of the function call (for `function_call_output` items). <br>  |


### Items in `content` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | No |  | `input_audio`, `input_text`, `item_reference`, `text` | The content type (`input_text`, `input_audio`, `item_reference`, `text`). <br>  |
| `text` | string | No |  |  | The text content, used for `input_text` and `text` content types. <br>  |
| `id` | string | No |  |  | ID of a previous conversation item to reference (for `item_reference` <br> content types in `response.create` events). These can reference both <br> client and server created items. <br>  |
| `audio` | string | No |  |  | Base64-encoded audio bytes, used for `input_audio` content type. <br>  |
| `transcript` | string | No |  |  | The transcript of the audio, used for `input_audio` content type. <br>  |

## Property Details

### `event_id`

Optional client-generated ID used to identify this event.

**Type**: string

### `type` (required)

The event type, must be `response.create`.

**Type**: string

**Allowed values**: `response.create`

### `response`

Create a new Realtime response with these parameters

**Type**: object (11 properties)

**Nested Properties**:

* `modalities`, `instructions`, `voice`, `output_audio_format`, `tools`, `tool_choice`, `temperature`, `max_response_output_tokens`, `conversation`, `metadata`, `input`

## Example

```json
{
    "event_id": "event_234",
    "type": "response.create",
    "response": {
        "modalities": ["text", "audio"],
        "instructions": "Please assist the user.",
        "voice": "sage",
        "output_audio_format": "pcm16",
        "tools": [
            {
                "type": "function",
                "name": "calculate_sum",
                "description": "Calculates the sum of two numbers.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "a": { "type": "number" },
                        "b": { "type": "number" }
                    },
                    "required": ["a", "b"]
                }
            }
        ],
        "tool_choice": "auto",
        "temperature": 0.8,
        "max_output_tokens": 1024
    }
}

```

