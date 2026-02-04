# conversation.item.retrieve

Send this event when you want to retrieve the server's representation of a specific item in the conversation history. This is useful, for example, to inspect user audio after noise cancellation and VAD.
The server will respond with a `conversation.item.retrieved` event, 
unless the item does not exist in the conversation history, in which case the 
server will respond with an error.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | No |  |  | Optional client-generated ID used to identify this event. |
| `type` | string | Yes |  | `conversation.item.retrieve` | The event type, must be `conversation.item.retrieve`. |
| `item_id` | string | Yes |  |  | The ID of the item to retrieve. |

## Property Details

### `event_id`

Optional client-generated ID used to identify this event.

**Type**: string

### `type` (required)

The event type, must be `conversation.item.retrieve`.

**Type**: string

**Allowed values**: `conversation.item.retrieve`

### `item_id` (required)

The ID of the item to retrieve.

**Type**: string

## Example

```json
{
    "event_id": "event_901",
    "type": "conversation.item.retrieve",
    "item_id": "msg_003"
}

```

