# conversation.item.delete

Send this event when you want to remove any item from the conversation 
history. The server will respond with a `conversation.item.deleted` event, 
unless the item does not exist in the conversation history, in which case the 
server will respond with an error.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | No |  |  | Optional client-generated ID used to identify this event. |
| `type` | string | Yes |  | `conversation.item.delete` | The event type, must be `conversation.item.delete`. |
| `item_id` | string | Yes |  |  | The ID of the item to delete. |

## Property Details

### `event_id`

Optional client-generated ID used to identify this event.

**Type**: string

### `type` (required)

The event type, must be `conversation.item.delete`.

**Type**: string

**Allowed values**: `conversation.item.delete`

### `item_id` (required)

The ID of the item to delete.

**Type**: string

## Example

```json
{
    "event_id": "event_901",
    "type": "conversation.item.delete",
    "item_id": "msg_003"
}

```

