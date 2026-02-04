# conversation.item.create

Add a new Item to the Conversation's context, including messages, function 
calls, and function call responses. This event can be used both to populate a 
"history" of the conversation and to add new items mid-stream, but has the 
current limitation that it cannot populate assistant audio messages.

If successful, the server will respond with a `conversation.item.created` 
event, otherwise an `error` event will be sent.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | No |  |  | Optional client-generated ID used to identify this event. |
| `type` | string | Yes |  | `conversation.item.create` | The event type, must be `conversation.item.create`. |
| `previous_item_id` | string | No |  |  | The ID of the preceding item after which the new item will be inserted.  <br> If not set, the new item will be appended to the end of the conversation. <br> If set to `root`, the new item will be added to the beginning of the conversation. <br> If set to an existing ID, it allows an item to be inserted mid-conversation. If the <br> ID cannot be found, an error will be returned and the item will not be added. <br>  |
| `item` | object (10 properties) | Yes |  |  | The item to add to the conversation. |
|   ↳ `object` | string | No |  | `realtime.item` | Identifier for the API object being returned - always `realtime.item`. <br>  |
|   ↳ `status` | string | No |  | `completed`, `incomplete` | The status of the item (`completed`, `incomplete`). These have no effect  <br> on the conversation, but are accepted for consistency with the  <br> `conversation.item.created` event. <br>  |
|   ↳ `role` | string | No |  | `user`, `assistant`, `system` | The role of the message sender (`user`, `assistant`, `system`), only  <br> applicable for `message` items. <br>  |
|   ↳ `content` | array of object (5 properties) | No |  |  | The content of the message, applicable for `message` items.  <br> - Message items of role `system` support only `input_text` content <br> - Message items of role `user` support `input_text` and `input_audio`  <br>   content <br> - Message items of role `assistant` support `text` content. <br>  |
|   ↳ `call_id` | string | No |  |  | The ID of the function call (for `function_call` and  <br> `function_call_output` items). If passed on a `function_call_output`  <br> item, the server will check that a `function_call` item with the same  <br> ID exists in the conversation history. <br>  |
|   ↳ `name` | string | No |  |  | The name of the function being called (for `function_call` items). <br>  |
|   ↳ `arguments` | string | No |  |  | The arguments of the function call (for `function_call` items). <br>  |
|   ↳ `output` | string | No |  |  | The output of the function call (for `function_call_output` items). <br>  |


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

The event type, must be `conversation.item.create`.

**Type**: string

**Allowed values**: `conversation.item.create`

### `previous_item_id`

The ID of the preceding item after which the new item will be inserted. 
If not set, the new item will be appended to the end of the conversation.
If set to `root`, the new item will be added to the beginning of the conversation.
If set to an existing ID, it allows an item to be inserted mid-conversation. If the
ID cannot be found, an error will be returned and the item will not be added.


**Type**: string

### `item` (required)

The item to add to the conversation.

**Type**: object (10 properties)

**Nested Properties**:

* `id`, `type`, `object`, `status`, `role`, `content`, `call_id`, `name`, `arguments`, `output`

## Example

```json
{
    "event_id": "event_345",
    "type": "conversation.item.create",
    "previous_item_id": null,
    "item": {
        "id": "msg_001",
        "type": "message",
        "role": "user",
        "content": [
            {
                "type": "input_text",
                "text": "Hello, how are you?"
            }
        ]
    }
}

```

