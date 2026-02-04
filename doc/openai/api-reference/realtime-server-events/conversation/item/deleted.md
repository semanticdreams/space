# conversation.item.deleted

Returned when an item in the conversation is deleted by the client with a 
`conversation.item.delete` event. This event is used to synchronize the 
server's understanding of the conversation history with the client's view.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `conversation.item.deleted` | The event type, must be `conversation.item.deleted`. |
| `item_id` | string | Yes |  |  | The ID of the item that was deleted. |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be `conversation.item.deleted`.

**Type**: string

**Allowed values**: `conversation.item.deleted`

### `item_id` (required)

The ID of the item that was deleted.

**Type**: string

## Example

```json
{
    "event_id": "event_2728",
    "type": "conversation.item.deleted",
    "item_id": "msg_005"
}

```

